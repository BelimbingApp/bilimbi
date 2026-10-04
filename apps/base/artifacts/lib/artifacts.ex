defmodule Bilimbi.Base.Artifacts do
  @moduledoc """
  Private, company-scoped documents with owning-module access rechecks.

  See docs/README.md for the trusted Owner/PDF adapters and lifecycle contract.
  Bytes are returned only after authorization, integrity validation and a
  committed audit action. No paths, public URLs, Ecto schemas or access tokens
  are exposed. All public operations must be called outside a Repo transaction:
  durable reservations and deletion tombstones must commit before filesystem IO.
  """
  import Ecto.Query

  alias Bilimbi.Base.Artifacts.{Schema, Storage}
  alias Bilimbi.Base.{Audit, Repo, Settings, Tenancy}
  alias Bilimbi.Base.Tenancy.Scope

  @type document_ref :: Bilimbi.Base.Artifacts.Owner.document_ref()
  @type metadata :: %{
          id: String.t(),
          subject: String.t(),
          kind: String.t(),
          content_type: String.t(),
          byte_size: pos_integer(),
          sha256: String.t(),
          expires_at: DateTime.t()
        }

  @spec put(Scope.t(), pos_integer(), module(), document_ref(), binary(), String.t()) ::
          {:ok, metadata()} | {:error, term()}
  def put(%Scope{} = scope, company, owner, reference, bytes, content_type)
      when is_integer(company) and company > 0 and is_atom(owner) and is_map(reference) and
             is_binary(bytes) and is_binary(content_type) do
    outside_transaction!()

    with :ok <- authorize(scope, company, owner, :create, reference),
         {:ok, root, days} <- storage_policy(bytes),
         {:ok, row} <- reserve(scope, company, owner, reference, bytes, content_type, root, days) do
      finalize(scope, company, owner, row, bytes)
    end
  end

  @spec generate_pdf(Scope.t(), pos_integer(), module(), document_ref(), map()) ::
          {:ok, metadata()} | {:error, term()}
  def generate_pdf(%Scope{} = scope, company, owner, reference, data)
      when is_integer(company) and company > 0 and is_atom(owner) and is_map(reference) and
             is_map(data) do
    outside_transaction!()

    with :ok <- authorize(scope, company, owner, :create, reference),
         true <- function_exported?(owner, :render_pdf, 4),
         {:ok, <<"%PDF-", _::binary>> = bytes} <-
           owner.render_pdf(scope, company, reference, data) do
      put(scope, company, owner, reference, bytes, "application/pdf")
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_pdf}
    end
  end

  @spec read(Scope.t(), pos_integer(), module(), String.t()) ::
          {:ok, %{metadata: metadata(), bytes: binary()}} | {:error, term()}
  def read(%Scope{} = scope, company, owner, id) do
    outside_transaction!()

    transaction(fn ->
      row = fetch!(scope, company, owner, id)
      require_ok!(authorize(scope, company, owner, :read, reference(row)))

      unless row.ready_at && is_nil(row.deleted_at) &&
               DateTime.before?(DateTime.utc_now(), row.expires_at),
             do: Repo.rollback(:not_found)

      bytes =
        case Storage.read(row.storage_root, row.id) do
          {:ok, bytes} -> bytes
          {:error, reason} -> Repo.rollback(reason)
        end

      unless byte_size(bytes) == row.byte_size and digest(bytes) == row.sha256,
        do: Repo.rollback(:integrity_failure)

      audit!(scope, row, "artifacts.read")
      %{metadata: metadata(row), bytes: bytes}
    end)
  end

  @spec delete(Scope.t(), pos_integer(), module(), String.t()) ::
          {:ok, :deleted} | {:error, term()}
  def delete(%Scope{} = scope, company, owner, id) do
    outside_transaction!()

    with {:ok, row} <- tombstone(scope, company, owner, id) do
      cleanup(scope, company, owner, row.id)
    end
  end

  @doc """
  Processes a bounded owner/company batch of expired documents and unfinished deletes.

  A failed or refused purge records its attempt and is skipped until the retry
  interval passes; after the configured maximum attempts it is held for an operator.
  """
  @spec purge_expired(Scope.t(), pos_integer(), module()) :: {:ok, map()} | {:error, term()}
  def purge_expired(%Scope{} = scope, company, owner) do
    outside_transaction!()

    with :ok <- authorize(scope, company, owner, :purge, nil) do
      now = DateTime.utc_now()
      retry_before = DateTime.add(now, -Settings.get("artifacts.purge_retry_minutes"), :minute)

      ids =
        scope
        |> owned_query(company, owner)
        |> where([a], is_nil(a.purged_at) and is_nil(a.purge_held_at))
        |> where([a], a.expires_at <= ^now or not is_nil(a.deleted_at))
        |> where([a], is_nil(a.purge_attempted_at) or a.purge_attempted_at <= ^retry_before)
        |> order_by([a], asc: a.expires_at, asc: a.id)
        |> limit(^Settings.get("artifacts.purge_batch_size"))
        |> select([a], a.id)
        |> Repo.all()

      results = Enum.map(ids, &{&1, purge(scope, company, owner, &1)})

      {:ok,
       %{
         deleted: for({id, {:ok, :deleted}} <- results, do: id),
         errors: for({id, {:error, reason}} <- results, do: {id, reason})
       }}
    end
  end

  @doc "Lists the owner/company documents whose purge is held for an operator."
  @spec list_purge_holds(Scope.t(), pos_integer(), module()) ::
          {:ok, [map()]} | {:error, term()}
  def list_purge_holds(%Scope{} = scope, company, owner) do
    with :ok <- authorize(scope, company, owner, :purge, nil) do
      holds =
        scope
        |> owned_query(company, owner)
        |> where([a], is_nil(a.purged_at) and not is_nil(a.purge_held_at))
        |> order_by([a], asc: a.purge_held_at, asc: a.id)
        |> Repo.all()
        |> Enum.map(fn row ->
          Map.merge(metadata(row), %{
            attempts: row.purge_attempts,
            last_error: row.purge_last_error,
            last_attempted_at: row.purge_attempted_at,
            held_at: row.purge_held_at
          })
        end)

      {:ok, holds}
    end
  end

  @doc "Releases a held purge and attempts it immediately, rechecking delete access."
  @spec retry_purge(Scope.t(), pos_integer(), module(), String.t()) ::
          {:ok, :deleted} | {:error, term()}
  def retry_purge(%Scope{} = scope, company, owner, id) do
    outside_transaction!()

    with :ok <- authorize(scope, company, owner, :purge, nil),
         {:ok, _} <-
           transaction(fn ->
             row = fetch_held!(scope, company, owner, id)
             audit!(scope, row, "artifacts.purge_released", purge_payload(row))

             row
             |> Ecto.Changeset.change(
               purge_attempts: 0,
               purge_last_error: nil,
               purge_attempted_at: nil,
               purge_held_at: nil
             )
             |> Repo.update!()
           end) do
      purge(scope, company, owner, id)
    end
  end

  @doc """
  Resolves a held purge whose bytes an operator has removed out of band.

  Refuses while the private file is still present.
  """
  @spec resolve_purge(Scope.t(), pos_integer(), module(), String.t()) ::
          {:ok, :resolved} | {:error, term()}
  def resolve_purge(%Scope{} = scope, company, owner, id) do
    outside_transaction!()

    with :ok <- authorize(scope, company, owner, :purge, nil),
         {:ok, _} <-
           transaction(fn ->
             row = fetch_held!(scope, company, owner, id)
             require_ok!(Storage.absent(row.storage_root, row.id))
             audit!(scope, row, "artifacts.purge_resolved", purge_payload(row))
             now = DateTime.utc_now()

             row
             |> Ecto.Changeset.change(
               deleted_at: row.deleted_at || now,
               purged_at: now,
               purge_held_at: nil
             )
             |> Repo.update!()
           end) do
      {:ok, :resolved}
    end
  end

  defp purge(scope, company, owner, id) do
    case delete(scope, company, owner, id) do
      {:error, reason} = error ->
        record_purge_failure(scope, company, owner, id, reason)
        error

      deleted ->
        deleted
    end
  end

  defp record_purge_failure(scope, company, owner, id, reason) do
    error = if is_atom(reason), do: String.slice(Atom.to_string(reason), 0, 255), else: "error"
    max_attempts = Settings.get("artifacts.purge_max_attempts")

    transaction(fn ->
      now = DateTime.utc_now()
      row = fetch!(scope, company, owner, id)
      attempts = row.purge_attempts + 1
      held_at = if attempts >= max_attempts, do: now

      row =
        row
        |> Ecto.Changeset.change(
          purge_attempts: attempts,
          purge_last_error: error,
          purge_attempted_at: now,
          purge_held_at: held_at
        )
        |> Repo.update!()

      audit!(scope, row, "artifacts.purge_failed", purge_payload(row))
      if held_at, do: audit!(scope, row, "artifacts.purge_held", purge_payload(row))
    end)
  end

  defp fetch_held!(scope, company, owner, id) do
    row = fetch!(scope, company, owner, id)
    if row.purge_held_at && is_nil(row.purged_at), do: row, else: Repo.rollback(:not_found)
  end

  defp purge_payload(row), do: %{attempts: row.purge_attempts, reason: row.purge_last_error}

  defp owned_query(scope, company, owner) do
    owner_id = owner.artifact_owner_id()
    adapter = Atom.to_string(owner)

    Schema
    |> Tenancy.scope_query(scope)
    |> where(
      [a],
      a.company_id == ^company and a.owner_id == ^owner_id and a.owner_adapter == ^adapter
    )
  end

  defp reserve(scope, company, owner, ref, bytes, content_type, root, days) do
    attrs = %{
      id: Ecto.UUID.generate(),
      tenant_id: Scope.tenant_id(scope),
      company_id: company,
      owner_id: owner.artifact_owner_id(),
      owner_adapter: Atom.to_string(owner),
      subject: Map.get(ref, :subject),
      kind: Map.get(ref, :kind),
      content_type: content_type,
      byte_size: byte_size(bytes),
      sha256: digest(bytes),
      storage_root: root,
      expires_at: DateTime.add(DateTime.utc_now(), days, :day)
    }

    transaction(fn ->
      case Repo.insert(Schema.changeset(attrs)) do
        {:ok, row} -> row
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp finalize(scope, company, owner, row, bytes) do
    result =
      transaction(fn ->
        stored = fetch!(scope, company, owner, row.id)
        require_ok!(authorize(scope, company, owner, :create, reference(stored)))
        unless is_nil(stored.deleted_at), do: Repo.rollback(:not_found)

        # Hold the reservation lock during creation: maintenance must not mark
        # a reservation purged before a delayed writer creates its file.
        require_ok!(Storage.write(stored.storage_root, stored.id, bytes))
        require_ok!(authorize(scope, company, owner, :create, reference(stored)))

        stored
        |> Ecto.Changeset.change(ready_at: DateTime.utc_now())
        |> Repo.update!()
        |> metadata()
      end)

    case result do
      {:ok, _} ->
        result

      {:error, _} ->
        discard_reservation(scope, owner, row)
        result
    end
  end

  defp discard_reservation(scope, owner, row) do
    # A failed upload leaves an inaccessible, auditable tombstone; retention
    # retries physical cleanup even after a crash or filesystem outage.
    Repo.update!(Ecto.Changeset.change(row, deleted_at: DateTime.utc_now()))
    cleanup(scope, row.company_id, owner, row.id)
  end

  defp tombstone(scope, company, owner, id) do
    transaction(fn ->
      row = fetch!(scope, company, owner, id)
      require_ok!(authorize(scope, company, owner, :delete, reference(row)))

      if row.deleted_at do
        row
      else
        audit!(scope, row, "artifacts.delete")
        row |> Ecto.Changeset.change(deleted_at: DateTime.utc_now()) |> Repo.update!()
      end
    end)
  end

  defp cleanup(scope, company, owner, id) do
    transaction(fn ->
      row = fetch!(scope, company, owner, id)

      if is_nil(row.purged_at) do
        require_ok!(Storage.delete(row.storage_root, row.id))
        audit!(scope, row, "artifacts.purge")
        Repo.update!(Ecto.Changeset.change(row, purged_at: DateTime.utc_now()))
      end

      :deleted
    end)
  end

  defp fetch!(scope, company, owner, id) do
    require_ok!(company_access(scope, company))

    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        row =
          scope
          |> owned_query(company, owner)
          |> where([a], a.id == ^uuid)
          |> lock("FOR UPDATE")
          |> Repo.one()

        row || Repo.rollback(:not_found)

      :error ->
        Repo.rollback(:not_found)
    end
  end

  defp authorize(scope, company, owner, operation, ref) do
    with :ok <- company_access(scope, company) do
      case owner.authorize(scope, company, operation, ref) do
        :ok -> :ok
        _ -> {:error, :forbidden}
      end
    end
  end

  defp company_access(scope, company) do
    actor = Scope.actor(scope)
    if actor.company_id && actor.company_id != company, do: {:error, :forbidden}, else: :ok
  end

  defp storage_policy(bytes) do
    root = Settings.get("artifacts.storage_root")
    days = Settings.get("artifacts.retention_days")
    max = Settings.get("artifacts.max_bytes")

    cond do
      not is_integer(days) or days < 1 ->
        {:error, :retention_not_configured}

      byte_size(bytes) == 0 or byte_size(bytes) > max ->
        {:error, :invalid_size}

      true ->
        case Storage.validate_root(root) do
          :ok -> {:ok, root, days}
          error -> error
        end
    end
  end

  defp audit!(scope, row, event, details \\ %{}) do
    actor = Scope.actor(scope)

    attrs = %{
      company_id: row.company_id,
      actor_type: if(actor.type == :user, do: "user", else: "guest"),
      actor_id: actor.user_id || 0,
      impersonator_id: actor.impersonator_id,
      event: event,
      payload: Map.merge(details, %{artifact_id: row.id, owner_id: row.owner_id}),
      occurred_at: NaiveDateTime.utc_now()
    }

    attrs =
      if actor.system_principal,
        do: Map.merge(attrs, %{actor_type: "system", system_principal: actor.system_principal}),
        else: attrs

    case Audit.record_action(scope, attrs) do
      {:ok, _} -> :ok
      {:error, _} -> Repo.rollback(:audit_unavailable)
    end
  rescue
    _error in [Postgrex.Error, Ecto.ConstraintError] -> Repo.rollback(:audit_unavailable)
  end

  defp metadata(row),
    do: Map.take(row, [:id, :subject, :kind, :content_type, :byte_size, :sha256, :expires_at])

  defp reference(row), do: Map.take(row, [:subject, :kind])
  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp require_ok!(:ok), do: :ok
  defp require_ok!({:error, reason}), do: Repo.rollback(reason)
  defp transaction(fun), do: Repo.transact(fn -> {:ok, fun.()} end)

  defp outside_transaction! do
    if Repo.in_transaction?(),
      do: raise(ArgumentError, "artifact operations require a committed filesystem boundary")
  end
end
