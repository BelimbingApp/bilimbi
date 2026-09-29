defmodule Bilimbi.Base.Grid.Table do
  @moduledoc """
  One table of the grid catalog, as its owning module declared it.

  `id` is the stable, URL-safe name (`users`, `companies`), unique across
  every installed module. `capability` is what an account needs to read any
  of its rows, checked before a path may touch the table. `source` implements
  `Bilimbi.Base.Grid.Source`. `key` names the field that identifies a row,
  `label_field` the one that names it to a person, and `time_field` the one a
  rollup orders by for "latest" and buckets by for a trend. `record_kind` is
  the stable module id whose workspace facts (`Bilimbi.Base.UI.Workspace`)
  name a row of this table by its key, such as `"core/company"` for
  `companies`; a module has at most one such table.
  """

  alias Bilimbi.Base.Grid.Field
  alias Bilimbi.Base.Grid.Link

  @keys [
    :id,
    :label,
    :capability,
    :source,
    :key,
    :label_field,
    :time_field,
    :record_kind,
    :fields,
    :links
  ]
  @id_pattern ~r/^[a-z][a-z0-9_]*$/

  @enforce_keys [:id, :label, :capability, :source, :key, :owner]
  defstruct id: nil,
            label: nil,
            capability: nil,
            source: nil,
            key: nil,
            label_field: nil,
            time_field: nil,
            record_kind: nil,
            fields: %{},
            field_order: [],
            links: %{},
            link_order: [],
            owner: nil

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          capability: String.t(),
          source: module(),
          key: String.t(),
          label_field: String.t() | nil,
          time_field: String.t() | nil,
          record_kind: String.t() | nil,
          fields: %{String.t() => Field.t()},
          field_order: [String.t()],
          links: %{String.t() => Link.t()},
          link_order: [String.t()],
          owner: String.t()
        }

  @doc false
  @spec new!(map(), String.t()) :: {t(), [Link.t()]}
  def new!(attrs, owner) when is_map(attrs) do
    unknown = Map.keys(attrs) -- @keys

    if unknown != [] do
      invalid!(owner, attrs, "unknown keys #{inspect(unknown)}")
    end

    id = fetch_string!(attrs, :id, owner)

    unless Regex.match?(@id_pattern, id) do
      invalid!(owner, attrs, "table id #{inspect(id)} must match #{inspect(@id_pattern)}")
    end

    source = Map.get(attrs, :source)

    unless is_atom(source) and not is_nil(source) do
      invalid!(owner, attrs, "table #{id} source must be a module")
    end

    fields =
      attrs
      |> Map.get(:fields, [])
      |> List.wrap()
      |> Enum.map(&Field.new!(&1, owner))

    field_ids = Enum.map(fields, & &1.id)

    if Enum.uniq(field_ids) != field_ids do
      invalid!(owner, attrs, "table #{id} declares a field twice")
    end

    if fields == [] do
      invalid!(owner, attrs, "table #{id} declares no fields")
    end

    key = fetch_string!(attrs, :key, owner)
    field_map = Map.new(fields, &{&1.id, &1})

    for {name, field_id} <- [
          key: key,
          label_field: Map.get(attrs, :label_field),
          time_field: Map.get(attrs, :time_field)
        ],
        not is_nil(field_id),
        not Map.has_key?(field_map, field_id) do
      invalid!(owner, attrs, "table #{id} #{name} #{inspect(field_id)} is not a declared field")
    end

    with %Field{type: type} <- Map.get(field_map, Map.get(attrs, :time_field)),
         false <- type in [:date, :datetime] do
      invalid!(owner, attrs, "table #{id} time_field must be a date or datetime field")
    end

    links =
      attrs
      |> Map.get(:links, [])
      |> List.wrap()
      |> Enum.map(&Link.new!(&1, id, owner))

    table = %__MODULE__{
      id: id,
      label: Map.get(attrs, :label, String.capitalize(id)),
      capability: fetch_string!(attrs, :capability, owner),
      source: source,
      key: key,
      label_field: Map.get(attrs, :label_field),
      time_field: Map.get(attrs, :time_field),
      record_kind: record_kind!(attrs, id, owner),
      fields: field_map,
      field_order: field_ids,
      owner: owner
    }

    {table, links}
  end

  @doc "The declared fields, in declaration order, without the hidden ones."
  @spec visible_fields(t()) :: [Field.t()]
  def visible_fields(%__MODULE__{} = table) do
    table.field_order
    |> Enum.map(&Map.fetch!(table.fields, &1))
    |> Enum.reject(& &1.hidden)
  end

  @doc "The links that start at this table, in declaration order."
  @spec links(t()) :: [Link.t()]
  def links(%__MODULE__{} = table), do: Enum.map(table.link_order, &Map.fetch!(table.links, &1))

  @doc false
  @spec put_link(t(), Link.t()) :: t()
  def put_link(%__MODULE__{} = table, %Link{} = link) do
    %{
      table
      | links: Map.put(table.links, link.id, link),
        link_order: table.link_order ++ [link.id]
    }
  end

  @doc "The field that identifies a row."
  @spec key_field(t()) :: Field.t()
  def key_field(%__MODULE__{} = table), do: Map.fetch!(table.fields, table.key)

  defp record_kind!(attrs, id, owner) do
    case Map.get(attrs, :record_kind) do
      nil ->
        nil

      kind when is_binary(kind) ->
        if Regex.match?(~r{\A[a-z][a-z0-9_]*/[a-z][a-z0-9_]*\z}, kind),
          do: kind,
          else:
            invalid!(owner, attrs, "table #{id} record_kind #{inspect(kind)} is not a module id")

      other ->
        invalid!(
          owner,
          attrs,
          "table #{id} record_kind must be a module id, got #{inspect(other)}"
        )
    end
  end

  defp fetch_string!(attrs, key, owner) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> value
      other -> invalid!(owner, attrs, "#{key} must be a non-empty string, got #{inspect(other)}")
    end
  end

  defp invalid!(owner, attrs, message) do
    raise ArgumentError,
          "invalid grid table from #{owner} (#{inspect(Map.get(attrs, :id))}): #{message}"
  end
end
