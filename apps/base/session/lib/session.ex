defmodule Bilimbi.Base.Session do
  @moduledoc """
  Public API for the compatible, opaque durable session store.

  This module owns persistence and operational lifecycle only. It does not
  interpret payloads or authenticate users, and it has no dependency on Core
  User or Phoenix Web.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Session.Entry
  alias Bilimbi.Base.Session.Schema
  alias Bilimbi.Base.Session.Summary

  @default_limit 100
  @maximum_limit 500

  @spec put_session(String.t(), String.t(), map() | keyword()) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def put_session(id, payload, attributes \\ %{})
      when is_binary(id) and is_binary(payload) and
             (is_map(attributes) or is_list(attributes)) do
    id
    |> Schema.changeset(payload, attributes)
    |> Repo.insert(
      on_conflict: {
        :replace,
        [:user_id, :ip_address, :user_agent, :payload, :last_activity]
      },
      conflict_target: [:id],
      returning: true
    )
    |> case do
      {:ok, session} -> {:ok, Entry.from_schema(session)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec fetch_session(String.t()) :: {:ok, Entry.t()} | {:error, :not_found}
  def fetch_session(id) when is_binary(id) do
    case Repo.get(Schema, id) do
      nil -> {:error, :not_found}
      session -> {:ok, Entry.from_schema(session)}
    end
  end

  @spec list_sessions(keyword()) :: [Summary.t()]
  def list_sessions(opts \\ []) when is_list(opts) do
    opts = Keyword.validate!(opts, search: nil, limit: @default_limit)
    search = validate_search!(opts[:search])
    limit = validate_limit!(opts[:limit])

    Schema
    |> maybe_search(search)
    |> order_by([session], desc: session.last_activity, asc: session.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&Summary.from_schema/1)
  end

  @spec delete_session(String.t()) :: :ok
  def delete_session(id) when is_binary(id) do
    Repo.delete_all(from(session in Schema, where: session.id == ^id))
    :ok
  end

  @spec terminate_session(String.t(), String.t()) ::
          {:ok, :terminated | :not_found} | {:error, :current_session}
  def terminate_session(id, current_session_id)
      when is_binary(id) and is_binary(current_session_id) do
    if id == current_session_id do
      {:error, :current_session}
    else
      {count, _rows} = Repo.delete_all(from(session in Schema, where: session.id == ^id))
      {:ok, if(count == 1, do: :terminated, else: :not_found)}
    end
  end

  @doc """
  Terminates a user's durable sessions except the caller's current session.

  Returns the number of rows terminated as `{:ok, count}`. The caller must
  supply a positive durable user ID and a non-empty current session ID; invalid
  input has no fallback that could widen the deletion.

  The delete participates in an existing shared Repo transaction when one is
  open. It affects rows matched by this statement, not a credential epoch or a
  permanent login lockout: a session established after the statement outside
  that serialization can remain or appear later.

  Session payloads are opaque and are neither read nor returned by this
  lifecycle operation.
  """
  @spec terminate_user_sessions(pos_integer(), String.t()) :: {:ok, non_neg_integer()}
  def terminate_user_sessions(user_id, current_session_id)
      when is_integer(user_id) and user_id > 0 and is_binary(current_session_id) and
             byte_size(current_session_id) > 0 do
    {count, _rows} =
      Repo.delete_all(
        from(session in Schema,
          where: session.user_id == ^user_id and session.id != ^current_session_id
        )
      )

    {:ok, count}
  end

  @spec prune_expired(non_neg_integer()) :: non_neg_integer()
  def prune_expired(before_last_activity)
      when is_integer(before_last_activity) and before_last_activity >= 0 do
    {count, _rows} =
      Repo.delete_all(
        from(session in Schema, where: session.last_activity < ^before_last_activity)
      )

    count
  end

  defp maybe_search(query, nil), do: query

  defp maybe_search(query, search) do
    pattern = "%#{search}%"

    from(session in query,
      where:
        ilike(session.ip_address, ^pattern) or
          ilike(session.user_agent, ^pattern)
    )
  end

  defp validate_search!(nil), do: nil

  defp validate_search!(search) when is_binary(search) do
    case String.trim(search) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp validate_search!(search) do
    raise ArgumentError, "session search must be a string or nil, got: #{inspect(search)}"
  end

  defp validate_limit!(limit) when is_integer(limit) and limit in 1..@maximum_limit, do: limit

  defp validate_limit!(limit) do
    raise ArgumentError,
          "session limit must be between 1 and #{@maximum_limit}, got: #{inspect(limit)}"
  end
end
