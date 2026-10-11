defmodule Bilimbi.Base.Media.PrivateAttachmentStore do
  @moduledoc false
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]
  alias Bilimbi.Base.{Repo, Settings, Tenancy}
  alias Bilimbi.Base.Tenancy.Scope

  alias Bilimbi.Base.Media.{
    AssetStore,
    AttachmentSchema,
    AttachmentSubjectAuthorizerRegistry,
    Attribution,
    ULID,
    Upload
  }

  def upload(scope, {type, subject_id}, file, rules) do
    id = to_string(subject_id)

    with {:ok, actor} <- uploader(scope),
         :ok <- authorize(scope, :upload, type, id, []),
         {:ok, bytes, attrs} <- Upload.read(file, true, rules) do
      disk = Settings.get("media.attachment_disk")
      key = "tenants/#{Scope.tenant_id(scope)}/attachments/#{Ecto.UUID.generate()}"

      Attribution.run(scope, fn ->
        AssetStore.put(disk, key, bytes, attrs, fn attrs ->
          Repo.transact(fn ->
            # Recheck after reading the upload and before publishing the binding.
            with :ok <- authorize(scope, :upload, type, id, []),
                 {:ok, asset} <- AssetStore.original(disk, key, attrs) do
              row = %AttachmentSchema{
                public_id: ULID.generate(),
                tenant_id: Scope.tenant_id(scope),
                media_asset_id: asset.id,
                subject_type: type,
                subject_id: id,
                state: "draft",
                uploaded_by_type: "user",
                uploaded_by_id: actor.user_id
              }

              Repo.insert(row)
            end
          end)
        end)
      end)
      |> summary_result()
    end
  end

  def submit(scope, subject, ids), do: bind(scope, subject, ids, :submit)
  def retain(scope, subject, ids), do: bind(scope, subject, ids, :retain)

  defp bind(scope, {type, subject_id}, ids, operation) when is_list(ids) do
    ids = Enum.uniq(ids)
    id = to_string(subject_id)

    with {:ok, _actor} <- uploader(scope) do
      Attribution.run(scope, fn ->
        Repo.transact(fn ->
          rows =
            Repo.all(
              from a in Tenancy.scope_query(AttachmentSchema, scope),
                where: a.public_id in ^ids,
                order_by: a.id,
                lock: "FOR UPDATE"
            )

          cond do
            length(rows) != length(ids) ->
              {:error, :attachments_unavailable}

            Enum.any?(rows, &(&1.subject_type != type or &1.subject_id != id)) ->
              {:error, :wrong_subject}

            true ->
              with :ok <- authorize(scope, :submit, type, id, Enum.map(rows, &summary/1)) do
                now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

                updated =
                  Enum.map(rows, fn row ->
                    case {row.state, operation} do
                      {"submitted", _} ->
                        row

                      {"draft", :submit} ->
                        Repo.update!(change(row, state: "submitted", submitted_at: now))

                      {"draft", :retain} ->
                        Repo.update!(change(row, retained_at: now))

                      _ ->
                        Repo.rollback(:invalid_attachment_state)
                    end
                  end)

                {:ok, Enum.map(updated, &summary/1)}
              end
          end
        end)
      end)
    end
  end

  def discard(scope, public_id) do
    with {:ok, actor} <- uploader(scope) do
      remove(scope, public_id, fn row ->
        if row.uploaded_by_type != "user" or row.uploaded_by_id != actor.user_id,
          do: {:error, :not_uploader},
          else: :ok
      end)
    end
  end

  def cleanup(scope, cutoff) do
    ids =
      Repo.all(
        from a in Tenancy.scope_query(AttachmentSchema, scope),
          where: a.state == "draft" and is_nil(a.retained_at) and a.created_at < ^cutoff,
          order_by: a.id,
          select: a.public_id
      )

    Enum.reduce_while(ids, {:ok, 0}, fn id, {:ok, count} ->
      result =
        remove(scope, id, fn row ->
          if is_nil(row.retained_at) and NaiveDateTime.compare(row.created_at, cutoff) == :lt,
            do: :ok,
            else: {:error, :not_abandoned}
        end)

      case result do
        {:ok, :deleted} ->
          {:cont, {:ok, count + 1}}

        {:error, reason} when reason in [:not_found, :immutable_attachment, :not_abandoned] ->
          {:cont, {:ok, count}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  def download(scope, public_id) do
    with {:ok, _actor} <- uploader(scope),
         {:ok, row} <- fetch(scope, public_id),
         :ok <- authorize(scope, :download, row.subject_type, row.subject_id, [summary(row)]),
         {:ok, asset} <- AssetStore.fetch(row.media_asset_id),
         {:ok, bytes} <- Bilimbi.Base.Media.Storage.read(asset.disk, asset.storage_key) do
      {:ok,
       %{bytes: bytes, filename: asset.original_filename || Path.basename(asset.storage_key)}}
    end
  end

  defp remove(scope, public_id, check) do
    with {:ok, assets} <-
           Attribution.run(scope, fn ->
             Repo.transact(fn ->
               with {:ok, row} <- fetch(scope, public_id, true),
                    :ok <- draft(row),
                    :ok <- check.(row),
                    {:ok, _} <- Repo.delete(row) do
                 {:ok, AssetStore.delete_draft_asset!(row.media_asset_id)}
               end
             end)
           end) do
      AssetStore.cleanup(assets)
    end
  end

  defp fetch(scope, id, lock? \\ false) do
    query = from a in Tenancy.scope_query(AttachmentSchema, scope), where: a.public_id == ^id
    query = if lock?, do: lock(query, "FOR UPDATE"), else: query

    case Repo.one(query) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  defp draft(%{state: "draft"}), do: :ok
  defp draft(_), do: {:error, :immutable_attachment}

  defp uploader(scope) do
    case Scope.actor(scope) do
      %{type: :user, impersonator_id: nil} = actor -> {:ok, actor}
      _ -> {:error, :user_required}
    end
  end

  defp authorize(scope, action, type, id, rows),
    do: AttachmentSubjectAuthorizerRegistry.authorize(scope, action, type, id, rows)

  defp summary_result({:ok, row}), do: {:ok, summary(row)}
  defp summary_result(error), do: error

  defp summary(row),
    do:
      Map.take(row, [
        :public_id,
        :subject_type,
        :subject_id,
        :state,
        :uploaded_by_type,
        :uploaded_by_id,
        :submitted_at,
        :retained_at,
        :created_at
      ])
end
