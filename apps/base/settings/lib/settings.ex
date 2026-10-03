defmodule Bilimbi.Base.Settings do
  @moduledoc """
  Public API for declared runtime settings and claimed operational state.

  A declared setting resolves through only its allowed scopes and then its
  definition-owned default. A claimed runtime-state key has no default and
  returns `nil` when no row exists. Undeclared and unclaimed keys always fail.
  """

  import Ecto.Query

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings.Cache
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.Encryption
  alias Bilimbi.Base.Settings.Schema
  alias Bilimbi.Base.Settings.Scope

  @spec definition(String.t()) :: Definition.t() | nil
  def definition(key) when is_binary(key) and key != "" do
    definitions = registry!().definitions

    Map.get(definitions, key) ||
      definitions
      |> Map.values()
      |> Enum.filter(&String.contains?(&1.key, "*"))
      |> Enum.sort_by(&String.length(&1.key), :desc)
      |> Enum.find(&Definition.matches?(&1, key))
  end

  @spec definition!(String.t()) :: Definition.t()
  def definition!(key) do
    definition(key) || raise ArgumentError, "setting #{inspect(key)} has no discovered definition"
  end

  @spec definitions() :: %{required(String.t()) => Definition.t()}
  def definitions, do: registry!().definitions

  @spec runtime_claims() :: [String.t()]
  def runtime_claims, do: registry!().runtime_claims

  @spec get(String.t(), Scope.t() | nil) :: term()
  def get(key, scope \\ nil) when is_binary(key) and key != "" do
    case definition(key) do
      %Definition{} = definition ->
        scope
        |> Scope.chain()
        |> Enum.filter(&Definition.allows_scope?(definition, &1))
        |> first_override(key)
        |> case do
          :missing -> definition.default
          {:ok, value} -> value
        end

      nil ->
        assert_runtime_claimed!(key)

        case first_override(Scope.chain(scope), key) do
          :missing -> nil
          {:ok, value} -> value
        end
    end
  end

  @spec get_many([String.t()], Scope.t() | nil) :: %{required(String.t()) => term()}
  def get_many(keys, scope \\ nil) when is_list(keys) do
    keys = Enum.uniq(keys)

    definitions = Map.new(keys, &{&1, definition(&1)})

    keys
    |> Enum.flat_map(fn key ->
      definition = Map.fetch!(definitions, key)

      if definition do
        scope
        |> Scope.chain()
        |> Enum.filter(&Definition.allows_scope?(definition, &1))
        |> Enum.map(&{key, &1})
      else
        assert_runtime_claimed!(key)
        Enum.map(Scope.chain(scope), &{key, &1})
      end
    end)
    |> Enum.uniq()
    |> then(fn pairs ->
      rows = fetch_rows(pairs)

      Map.new(keys, fn key ->
        definition = Map.fetch!(definitions, key)

        value =
          pairs
          |> Enum.filter(fn {candidate_key, _scope} -> candidate_key == key end)
          |> Enum.reduce_while(nil, fn {_candidate_key, candidate_scope}, _acc ->
            case Map.fetch(rows, row_cache_key(key, candidate_scope)) do
              {:ok, %Schema{} = row} -> {:halt, {:found, decode(row)}}
              _ -> {:cont, nil}
            end
          end)
          |> case do
            {:found, value} -> value
            nil -> if(definition, do: definition.default, else: nil)
          end

        {key, value}
      end)
    end)
  end

  @spec put(String.t(), term(), Scope.t() | nil) :: {:ok, term()} | {:error, Ecto.Changeset.t()}
  def put(key, value, scope \\ nil) when is_binary(key) and key != "" do
    definition = definition(key)

    {stored_value, encrypted?} =
      case definition do
        %Definition{} = definition ->
          unless Definition.allows_scope?(definition, scope) do
            raise ArgumentError,
                  "setting #{inspect(key)} does not allow #{scope_name(scope)} scope"
          end

          if is_nil(value),
            do:
              raise(ArgumentError, "setting overrides cannot be nil; delete the override instead")

          unless Definition.accepts?(definition, value) do
            raise ArgumentError,
                  "setting #{inspect(key)} expects #{definition.type}, got #{inspect(value)}"
          end

          if definition.encrypted,
            do: {Encryption.encrypt!(value), true},
            else: {value, false}

        nil ->
          assert_runtime_claimed!(key)

          if is_nil(value),
            do:
              raise(
                ArgumentError,
                "runtime setting state cannot store nil; delete the row instead"
              )

          {value, false}
      end

    {scope_type, scope_id} = Scope.database_identity(scope)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    changeset =
      Schema.changeset(%Schema{}, %{
        key: key,
        value: stored_value,
        is_encrypted: encrypted?,
        scope_type: scope_type,
        scope_id: scope_id,
        created_at: now,
        updated_at: now
      })

    case definition && Definition.validate(definition, value) do
      {:error, message} ->
        changeset
        |> Ecto.Changeset.add_error(:value, message)
        |> Ecto.Changeset.apply_action(:insert)

      _valid ->
        changeset
        |> Repo.insert(
          on_conflict: {:replace, [:value, :is_encrypted, :updated_at]},
          conflict_target: conflict_target(scope)
        )
        |> case do
          {:ok, _setting} ->
            Cache.invalidate(key, scope_type, scope_id)
            {:ok, value}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @spec delete(String.t(), Scope.t() | nil) :: :ok
  def delete(key, scope \\ nil) when is_binary(key) and key != "" do
    assert_claimed_at_scope!(key, scope)
    {scope_type, scope_id} = Scope.database_identity(scope)

    key
    |> setting_scope_query(scope_type, scope_id)
    |> Repo.delete_all()

    Cache.invalidate(key, scope_type, scope_id)

    :ok
  end

  @spec overridden?(String.t(), Scope.t() | nil) :: boolean()
  def overridden?(key, scope \\ nil) when is_binary(key) and key != "" do
    assert_claimed_at_scope!(key, scope)
    not is_nil(fetch_row(key, scope))
  end

  defp first_override(scopes, key) do
    Enum.reduce_while(scopes, :missing, fn scope, :missing ->
      case fetch_row(key, scope) do
        nil -> {:cont, :missing}
        setting -> {:halt, {:ok, decode(setting)}}
      end
    end)
  end

  defp fetch_row(key, scope) do
    Cache.fetch(row_cache_key(key, scope), fn ->
      {scope_type, scope_id} = Scope.database_identity(scope)

      key
      |> setting_scope_query(scope_type, scope_id)
      |> limit(1)
      |> Repo.one()
    end)
  end

  defp fetch_rows(pairs) do
    cache_keys =
      Enum.map(pairs, fn {key, scope} ->
        {scope_type, scope_id} = Scope.database_identity(scope)
        {key, scope_type, scope_id}
      end)
      |> Enum.uniq()

    Cache.fetch_many(cache_keys, fn missing_keys ->
      filters =
        Enum.reduce(missing_keys, dynamic(false), fn {key, scope_type, scope_id}, filters ->
          scope_filter =
            if is_nil(scope_type) do
              dynamic([setting], is_nil(setting.scope_type) and is_nil(setting.scope_id))
            else
              dynamic(
                [setting],
                setting.scope_type == ^scope_type and setting.scope_id == ^scope_id
              )
            end

          dynamic([setting], ^filters or (setting.key == ^key and ^scope_filter))
        end)

      rows = from(setting in Schema, where: ^filters) |> Repo.all()

      by_identity =
        Map.new(rows, fn row ->
          {{row.key, row.scope_type, row.scope_id}, row}
        end)

      Map.new(missing_keys, fn cache_key ->
        {cache_key, Map.get(by_identity, cache_key)}
      end)
    end)
  end

  defp row_cache_key(key, %Scope{} = scope) do
    {scope_type, scope_id} = Scope.database_identity(scope)
    {key, scope_type, scope_id}
  end

  defp row_cache_key(key, nil), do: {key, nil, nil}

  defp setting_scope_query(key, nil, nil) do
    from(setting in Schema,
      where: setting.key == ^key,
      where: is_nil(setting.scope_type),
      where: is_nil(setting.scope_id)
    )
  end

  defp setting_scope_query(key, scope_type, scope_id) do
    from(setting in Schema,
      where: setting.key == ^key,
      where: setting.scope_type == ^scope_type,
      where: setting.scope_id == ^scope_id
    )
  end

  defp decode(%Schema{is_encrypted: true, value: value}), do: Encryption.decrypt!(value)
  defp decode(%Schema{value: value}), do: value

  defp registry!, do: ContributionRegistry.consumer!(:settings)

  defp assert_claimed_at_scope!(key, scope) do
    case definition(key) do
      %Definition{} = definition ->
        unless Definition.allows_scope?(definition, scope) do
          raise ArgumentError,
                "setting #{inspect(key)} does not allow #{scope_name(scope)} scope"
        end

      nil ->
        assert_runtime_claimed!(key)
    end

    :ok
  end

  defp assert_runtime_claimed!(key) do
    unless Enum.any?(runtime_claims(), &wildcard_match?(&1, key)) do
      raise ArgumentError, "setting #{inspect(key)} has no discovered definition or runtime claim"
    end
  end

  defp wildcard_match?(pattern, key) do
    pattern
    |> Regex.escape()
    |> String.replace("\\*", ".*")
    |> then(&Regex.compile!("^#{&1}$"))
    |> Regex.match?(key)
  end

  defp conflict_target(nil) do
    {:unsafe_fragment, "(key) WHERE scope_type IS NULL AND scope_id IS NULL"}
  end

  defp conflict_target(%Scope{}), do: [:key, :scope_type, :scope_id]
  defp scope_name(nil), do: :global
  defp scope_name(%Scope{type: type}), do: type
end
