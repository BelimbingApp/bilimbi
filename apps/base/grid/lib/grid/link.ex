defmodule Bilimbi.Base.Grid.Link do
  @moduledoc """
  A walkable relation between two catalog tables.

  A `:one` link reaches at most one row of `to` for each row of `from` and
  its fields become plain columns. A `:many` link reaches several and rolls
  them up into one cell. The join is either `on: {from_field, to_field}`, a
  pair of field ids on the two tables, or `via: {module, function}`, an edge
  query the declaring module owns (see `Bilimbi.Base.Grid.Source`).

  A module may declare a link that starts at another module's table by
  giving `from`, because the module that owns the edge is the one that knows
  it: an address module knows which company an address is attached to; the
  company module does not know the attachment table exists.
  """

  @keys [:id, :label, :from, :to, :kind, :on, :via]
  @id_pattern ~r/^[a-z][a-z0-9_]*$/

  @enforce_keys [:id, :label, :from, :to, :kind]
  defstruct id: nil, label: nil, from: nil, to: nil, kind: nil, on: nil, via: nil

  @type kind :: :one | :many

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          from: String.t(),
          to: String.t(),
          kind: kind(),
          on: {String.t(), String.t()} | nil,
          via: {module(), atom()} | nil
        }

  @doc false
  @spec new!(map(), String.t(), String.t()) :: t()
  def new!(attrs, declaring_table, owner) when is_map(attrs) do
    unknown = Map.keys(attrs) -- @keys

    if unknown != [] do
      invalid!(owner, attrs, "unknown keys #{inspect(unknown)}")
    end

    id = fetch_string!(attrs, :id, owner)

    unless Regex.match?(@id_pattern, id) do
      invalid!(owner, attrs, "link id #{inspect(id)} must match #{inspect(@id_pattern)}")
    end

    kind = Map.get(attrs, :kind)

    unless kind in [:one, :many] do
      invalid!(owner, attrs, "link #{id} kind must be :one or :many")
    end

    on = Map.get(attrs, :on)
    via = Map.get(attrs, :via)

    case {on, via} do
      {{from_field, to_field}, nil} when is_binary(from_field) and is_binary(to_field) ->
        :ok

      {nil, {module, function}} when is_atom(module) and is_atom(function) ->
        :ok

      _other ->
        invalid!(
          owner,
          attrs,
          "link #{id} needs exactly one of on: {from_field, to_field} or via: {module, function}"
        )
    end

    %__MODULE__{
      id: id,
      label: Map.get(attrs, :label, humanize(id)),
      from: Map.get(attrs, :from, declaring_table),
      to: fetch_string!(attrs, :to, owner),
      kind: kind,
      on: on,
      via: via
    }
  end

  defp fetch_string!(attrs, key, owner) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> value
      other -> invalid!(owner, attrs, "#{key} must be a non-empty string, got #{inspect(other)}")
    end
  end

  defp humanize(id), do: id |> String.replace("_", " ") |> String.capitalize()

  defp invalid!(owner, attrs, message) do
    raise ArgumentError, "invalid grid link from #{owner} (#{inspect(attrs)}): #{message}"
  end
end
