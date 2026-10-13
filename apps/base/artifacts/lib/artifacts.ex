defmodule Bilimbi.Base.Artifacts do
  @moduledoc """
  Private, company-scoped documents with owning-module access rechecks.

  See docs/README.md for the trusted Owner/PDF adapters and lifecycle contract.
  Bytes are returned only after authorization, integrity validation and a
  committed audit action. No paths, public URLs, Ecto schemas or access tokens
  are exposed. All public operations must be called outside a Repo transaction:
  durable reservations and deletion tombstones must commit before filesystem IO.

  A document is either ordinary or records-grade. An ordinary document carries
  `expires_at` from the operator's retention period: reads refuse it once that
  passes and maintenance purges it. A records-grade document carries
  `retain_until` instead, set by the owner at creation (`put/7`) or later
  (`retain/6`), and may be placed under a legal hold. It never expires: reads
  keep working until retain-until and after; deletion and purge are refused
  before retain-until or while on hold, first here and then by the database
  guard the migration installs; and retain-until only ever moves later. Every
  retention change is one append-only event stamped by PostgreSQL
  (`retention_history/4`) and one audit action.
  """
  import Ecto.Query

  alias Bilimbi.Base.Artifacts.{RetentionEvent, Schema, Storage}
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
          expires_at: DateTime.t() | nil,
          retain_until: DateTime.t() | nil,
          legal_hold_at: DateTime.t() | nil
        }
  @typedoc """
  Retention at creation: `retain_until` (a future instant) makes the document
  records-grade, `legal_hold: true` places it under hold at once, and `reason`
  (at most 255 characters, no document content) is kept on the event.
  """
  @type retention_option ::
          {:retain_until, DateTime.t()} | {:legal_hold, boolean()} | {:reason, String.t() | nil}
  @type retention_event :: %{
          event: String.t(),
          retain_until: DateTime.t(),
          legal_hold: boolean(),
          reason: String.t() | nil,
          actor_type: String.t(),
          actor_id: non_neg_integer(),
          impersonator_id: pos_integer() | nil,
          system_principal: String.t() | nil,
          recorded_at: DateTime.t()
        }

  @spec put(Scope.t(), pos_integer(), module(), document_ref(), binary(), String.t(), [
          retention_option()
        ]) ::
          {:ok, metadata()} | {:error, term()}
  def put(%Scope{} = scope, company, owner, reference, bytes, content_type, opts \\ [])
      when is_integer(company) and company > 0 and is_atom(owner) and is_map(reference) and
             is_binary(bytes) and is_binary(content_type) and is_list(opts) do
    outside_transaction!()

    with {:ok, retention} <- retention_request(opts),
         :ok <- authorize(scope, company, owner, :create, reference),
         :ok <- authorize_retention(scope, company, owner, reference, retention),
         {:ok, root, days} <- storage_policy(bytes),
         {:ok, row} <- reserve(scope, company, owner, reference, bytes, content_type, root, days) do
      finalize(scope, company, owner, row, bytes, retention)
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
      unless readable?(row, DateTime.utc_now()), do: Repo.rollback(:not_found)

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

  @doc """
  Deletes a document: an audited tombstone, then physical cleanup.

  A records-grade document is refused with `{:error, :legal_hold}` while on
  hold and `{:error, :retained}` before its retain-until; after retain-until
  it is deleted like any other, by an explicit call and never by maintenance.
  """
  @spec delete(Scope.t(), pos_integer(), module(), String.t()) ::
          {:ok, :deleted} | {:error, term()}
  def delete(%Scope{} = scope, company, owner, id) do
    outside_transaction!()

    with {:ok, row} <- tombstone(scope, company, owner, id) do
      cleanup(scope, company, owner, row.id)
    end
  end

  @doc """
  Makes a document records-grade, or moves its retain-until later.

  `retain_until` must be in the future and, for an already retained document,
  later than the current value (`{:error, :retention_not_extended}`); the
  database guard refuses anything earlier as well. The document loses its
  expiry for good. The owner authorizes `:retain`.
  """
  @spec retain(Scope.t(), pos_integer(), module(), String.t(), DateTime.t(), reason: String.t()) ::
          {:ok, metadata()} | {:error, term()}
  def retain(%Scope{} = scope, company, owner, id, %DateTime{} = retain_until, opts \\ [])
      when is_list(opts) do
    outside_transaction!()

    with {:ok, reason} <- retention_reason(opts),
         {:ok, %{retain_until: until}} <- retention_request(retain_until: retain_until) do
      transaction(fn ->
        row = fetch_retainable!(scope, company, owner, id)

        if row.retain_until && DateTime.compare(until, row.retain_until) != :gt,
          do: Repo.rollback(:retention_not_extended)

        event = if row.retain_until, do: "retention_extended", else: "retained"

        row
        |> Ecto.Changeset.change(retain_until: until, expires_at: nil)
        |> Repo.update!()
        |> record_retention!(scope, event, reason)
        |> metadata()
      end)
    end
  end

  @doc """
  Places a legal hold on a records-grade document.

  Deletion and purge are refused while the hold stands, whatever the
  retain-until. An ordinary document answers `{:error, :not_retained}`: retain
  it first. A held document answers `{:error, :already_on_hold}`.
  """
  @spec place_hold(Scope.t(), pos_integer(), module(), String.t(), reason: String.t()) ::
          {:ok, metadata()} | {:error, term()}
  def place_hold(%Scope{} = scope, company, owner, id, opts \\ []) when is_list(opts) do
    outside_transaction!()

    with {:ok, reason} <- retention_reason(opts) do
      transaction(fn ->
        row = fetch_retainable!(scope, company, owner, id)
        if is_nil(row.retain_until), do: Repo.rollback(:not_retained)
        if row.legal_hold_at, do: Repo.rollback(:already_on_hold)

        row
        |> Ecto.Changeset.change(legal_hold_at: DateTime.utc_now())
        |> Repo.update!()
        |> record_retention!(scope, "hold_placed", reason)
        |> metadata()
      end)
    end
  end

  @doc """
  Releases a legal hold; the retain-until keeps protecting the document.

  A document not on hold answers `{:error, :not_on_hold}`.
  """
  @spec release_hold(Scope.t(), pos_integer(), module(), String.t(), reason: String.t()) ::
          {:ok, metadata()} | {:error, term()}
  def release_hold(%Scope{} = scope, company, owner, id, opts \\ []) when is_list(opts) do
    outside_transaction!()

    with {:ok, reason} <- retention_reason(opts) do
      transaction(fn ->
        row = fetch_retainable!(scope, company, owner, id)
        unless row.legal_hold_at, do: Repo.rollback(:not_on_hold)

        row
        |> Ecto.Changeset.change(legal_hold_at: nil)
        |> Repo.update!()
        |> record_retention!(scope, "hold_released", reason)
        |> metadata()
      end)
    end
  end

  @doc """
  The document's retention events, oldest first, with who made each change
  and when the database recorded it. Requires `:read` access; a tombstoned
  document keeps its history.
  """
  @spec retention_history(Scope.t(), pos_integer(), module(), String.t()) ::
          {:ok, [retention_event()]} | {:error, term()}
  def retention_history(%Scope{} = scope, company, owner, id) do
    transaction(fn ->
      row = fetch!(scope, company, owner, id)
      require_ok!(authorize(scope, company, owner, :read, reference(row)))

      RetentionEvent
      |> Tenancy.scope_query(scope)
      |> where([e], e.artifact_id == ^row.id)
      |> order_by([e], asc: e.id)
      |> Repo.all()
      |> Enum.map(
        &Map.take(&1, [
          :event,
          :retain_until,
          :legal_hold,
          :reason,
          :actor_type,
          :actor_id,
          :impersonator_id,
          :system_principal,
          :recorded_at
        ])
      )
    end)
  end

  @doc """
  Processes a bounded owner/company batch of expired documents and unfinished deletes.

  A failed or refused purge records its attempt and is skipped until the retry
  interval passes; after the configured maximum attempts it is held for an operator.
  A records-grade document has no expiry and is never selected unless an
  explicit delete already tombstoned it.
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

  # A retention change needs the owner's `:retain` grant on a complete,
  # undeleted document; a reservation or tombstone is not found.
  defp fetch_retainable!(scope, company, owner, id) do
    row = fetch!(scope, company, owner, id)
    require_ok!(authorize(scope, company, owner, :retain, reference(row)))
    if row.ready_at && is_nil(row.deleted_at), do: row, else: Repo.rollback(:not_found)
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

  defp finalize(scope, company, owner, row, bytes, retention) do
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
        |> retain_at_creation!(scope, company, owner, retention)
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

  # Retention is applied to the complete document, in the publication
  # transaction: a failed upload stays an ordinary reservation that the usual
  # tombstone and purge can clean up, which the guard would refuse once retained.
  defp retain_at_creation!(row, _scope, _company, _owner, nil), do: row

  defp retain_at_creation!(row, scope, company, owner, retention) do
    require_ok!(authorize(scope, company, owner, :retain, reference(row)))
    hold_at = if retention.legal_hold, do: DateTime.utc_now()

    row
    |> Ecto.Changeset.change(
      retain_until: retention.retain_until,
      legal_hold_at: hold_at,
      expires_at: nil
    )
    |> Repo.update!()
    |> record_retention!(scope, "retained", retention.reason)
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

      cond do
        row.deleted_at ->
          row

        row.legal_hold_at ->
          Repo.rollback(:legal_hold)

        row.retain_until && DateTime.after?(row.retain_until, DateTime.utc_now()) ->
          Repo.rollback(:retained)

        true ->
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

  @doc false
  def authorize(scope, company, owner, operation, ref) do
    with :ok <- company_access(scope, company) do
      case owner.authorize(scope, company, operation, ref) do
        :ok -> :ok
        _ -> {:error, :forbidden}
      end
    end
  end

  defp authorize_retention(_scope, _company, _owner, _ref, nil), do: :ok

  defp authorize_retention(scope, company, owner, ref, _retention),
    do: authorize(scope, company, owner, :retain, ref)

  defp company_access(scope, company) do
    actor = Scope.actor(scope)
    if actor.company_id && actor.company_id != company, do: {:error, :forbidden}, else: :ok
  end

  # A records-grade document is readable until deleted; an ordinary one until
  # its expiry.
  defp readable?(row, now) do
    row.ready_at && is_nil(row.deleted_at) &&
      (is_nil(row.expires_at) or DateTime.before?(now, row.expires_at))
  end

  defp retention_request(opts) do
    with {:ok, opts} <- validate_options(opts, retain_until: nil, legal_hold: false, reason: nil),
         {:ok, reason} <- valid_reason(Keyword.fetch!(opts, :reason)) do
      case {Keyword.fetch!(opts, :retain_until), Keyword.fetch!(opts, :legal_hold)} do
        {nil, false} ->
          {:ok, nil}

        {%DateTime{time_zone: "Etc/UTC", microsecond: {micro, _}} = until, hold}
        when is_boolean(hold) ->
          until = %{until | microsecond: {micro, 6}}

          if DateTime.after?(until, DateTime.utc_now()),
            do: {:ok, %{retain_until: until, legal_hold: hold, reason: reason}},
            else: {:error, :invalid_retention}

        _ ->
          {:error, :invalid_retention}
      end
    end
  end

  defp retention_reason(opts) do
    with {:ok, opts} <- validate_options(opts, reason: nil) do
      valid_reason(Keyword.fetch!(opts, :reason))
    end
  end

  defp validate_options(opts, defaults) do
    case Keyword.validate(opts, defaults) do
      {:ok, opts} -> {:ok, opts}
      {:error, _unknown} -> {:error, :invalid_retention}
    end
  end

  defp valid_reason(nil), do: {:ok, nil}
  defp valid_reason(reason) when is_binary(reason) and byte_size(reason) <= 255, do: {:ok, reason}
  defp valid_reason(_reason), do: {:error, :invalid_retention}

  defp record_retention!(row, scope, event, reason) do
    attrs =
      Map.merge(actor_attribution(scope), %{
        artifact_id: row.id,
        tenant_id: row.tenant_id,
        company_id: row.company_id,
        owner_id: row.owner_id,
        event: event,
        retain_until: row.retain_until,
        legal_hold: not is_nil(row.legal_hold_at),
        reason: reason
      })

    case Repo.insert(RetentionEvent.changeset(attrs)) do
      {:ok, _} -> :ok
      {:error, _changeset} -> Repo.rollback(:invalid_retention)
    end

    audit!(scope, row, "artifacts." <> event, %{
      retain_until: DateTime.to_iso8601(row.retain_until),
      legal_hold: not is_nil(row.legal_hold_at)
    })

    row
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
    attrs = %{
      company_id: row.company_id,
      event: event,
      payload: Map.merge(details, %{artifact_id: row.id, owner_id: row.owner_id}),
      occurred_at: NaiveDateTime.utc_now()
    }

    case Audit.record_action(scope, attrs) do
      {:ok, _} -> :ok
      {:error, _} -> Repo.rollback(:audit_unavailable)
    end
  rescue
    _error in [Postgrex.Error, Ecto.ConstraintError] -> Repo.rollback(:audit_unavailable)
  end

  # Who the scope says performed the operation, in the shape the audit action
  # and the retention event both record.
  defp actor_attribution(scope) do
    scope
    |> Bilimbi.Base.Audit.Context.from_scope()
    |> Map.from_struct()
    |> Map.take([:actor_type, :actor_id, :impersonator_id, :system_principal])
  end

  defp metadata(row),
    do:
      Map.take(row, [
        :id,
        :subject,
        :kind,
        :content_type,
        :byte_size,
        :sha256,
        :expires_at,
        :retain_until,
        :legal_hold_at
      ])

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
