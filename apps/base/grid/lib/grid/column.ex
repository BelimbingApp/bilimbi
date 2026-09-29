defmodule Bilimbi.Base.Grid.Column do
  @moduledoc """
  One column of a grid: a path walked from the root table to a field, and,
  after a `:many` link, how the reached rows roll up into one cell.

  The spec is the column's stable text form, used in URLs and saved views:

      name                          a field of the root table
      company.name                  a field reached through one-links
      employees:count               rows reached through a many-link, counted
      employees.employment_start:max  a field of those rows, aggregated
      company.employees.department.status:list   one-links may follow the many-link

  A path holds at most one `:many` link, and a path through one must end in
  an aggregate. `count` takes no field; every other aggregate needs one.
  """

  alias Bilimbi.Base.Grid.Field
  alias Bilimbi.Base.Grid.Link
  alias Bilimbi.Base.Grid.Table

  @aggregates [:count, :sum, :avg, :min, :max, :latest, :list]
  @spec_pattern ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*(:(count|sum|avg|min|max|latest|list))?$/

  @enforce_keys [
    :spec,
    :id,
    :label,
    :type,
    :kind,
    :root,
    :table,
    :hops,
    :many,
    :tail,
    :field,
    :agg
  ]
  defstruct spec: nil,
            id: nil,
            label: nil,
            short_label: nil,
            type: nil,
            kind: nil,
            root: nil,
            table: nil,
            hops: [],
            many: nil,
            tail: [],
            field: nil,
            agg: nil,
            sortable: true,
            depth: 0

  @type agg :: :count | :sum | :avg | :min | :max | :latest | :list

  @type t :: %__MODULE__{
          spec: String.t(),
          id: String.t(),
          label: String.t(),
          short_label: String.t(),
          type: Field.type() | :count,
          kind: :field | :rollup,
          root: Table.t(),
          table: Table.t(),
          hops: [Link.t()],
          many: Link.t() | nil,
          tail: [Link.t()],
          field: Field.t() | nil,
          agg: agg() | nil,
          sortable: boolean(),
          depth: non_neg_integer()
        }

  @doc "The rollup aggregates a spec may end in."
  @spec aggregates() :: [agg()]
  def aggregates, do: @aggregates

  @doc "Whether the spec is well formed, before the catalog is consulted."
  @spec well_formed?(String.t()) :: boolean()
  def well_formed?(spec) when is_binary(spec), do: Regex.match?(@spec_pattern, spec)
  def well_formed?(_spec), do: false

  @doc """
  Resolves `spec` against `root`, with `fetch_table` returning a visible table
  by id or `:error`. Every table on the path must be visible, so a path
  through a table the account may not read fails as `:forbidden` the same way
  an unknown table does: the catalog the caller holds already left it out.
  """
  @spec resolve(String.t(), Table.t(), (String.t() -> {:ok, Table.t()} | :error)) ::
          {:ok, t()} | {:error, term()}
  def resolve(spec, %Table{} = root, fetch_table) when is_function(fetch_table, 1) do
    with true <- well_formed?(spec) || {:error, {:malformed, spec}},
         {segments, agg} <- split(spec),
         {:ok, walk} <-
           walk(segments, root, fetch_table, %{
             hops: [],
             many: nil,
             tail: [],
             field: nil,
             table: root
           }) do
      build(spec, root, walk, agg)
    end
  end

  defp split(spec) do
    case String.split(spec, ":", parts: 2) do
      [path] -> {String.split(path, "."), nil}
      [path, agg] -> {String.split(path, "."), String.to_existing_atom(agg)}
    end
  end

  defp walk([], _root, _fetch, acc), do: {:ok, acc}

  defp walk([segment | rest], root, fetch, %{table: table} = acc) do
    cond do
      Map.has_key?(table.links, segment) ->
        link = Map.fetch!(table.links, segment)

        with {:ok, target} <- fetch_visible(fetch, link) do
          acc =
            case {link.kind, acc.many} do
              {:one, nil} -> %{acc | hops: acc.hops ++ [link]}
              {:one, _many} -> %{acc | tail: acc.tail ++ [link]}
              {:many, nil} -> %{acc | many: link}
              {:many, _many} -> nil
            end

          if is_nil(acc) do
            {:error, {:second_many_link, segment}}
          else
            walk(rest, root, fetch, %{acc | table: target})
          end
        end

      Map.has_key?(table.fields, segment) and rest == [] ->
        field = Map.fetch!(table.fields, segment)

        if field.hidden do
          {:error, {:unknown_segment, segment, table.id}}
        else
          {:ok, %{acc | field: field}}
        end

      true ->
        {:error, {:unknown_segment, segment, table.id}}
    end
  end

  defp fetch_visible(fetch, %Link{to: to}) do
    case fetch.(to) do
      {:ok, %Table{} = table} -> {:ok, table}
      :error -> {:error, {:forbidden_table, to}}
    end
  end

  # A path with no many-link is a plain field column. A path through a
  # many-link is a rollup and must say how the rows collapse.
  defp build(spec, _root, %{many: nil, field: nil}, _agg), do: {:error, {:no_field, spec}}

  defp build(spec, root, %{many: nil} = walk, nil) do
    field = walk.field

    {:ok,
     %__MODULE__{
       spec: spec,
       id: dom_id(spec),
       label: label(walk.hops, [], field.label),
       short_label: short_label(walk.hops, field.label),
       type: field.type,
       kind: :field,
       root: root,
       table: walk.table,
       hops: walk.hops,
       many: nil,
       tail: [],
       field: field,
       agg: nil,
       sortable: field.sortable,
       depth: length(walk.hops)
     }}
  end

  defp build(spec, _root, %{many: nil}, _agg), do: {:error, {:aggregate_without_many_link, spec}}
  defp build(spec, _root, %{many: %Link{}}, nil), do: {:error, {:many_link_needs_aggregate, spec}}

  defp build(spec, _root, %{many: %Link{}, field: nil}, agg) when agg != :count,
    do: {:error, {:aggregate_needs_field, spec}}

  defp build(spec, _root, %{many: %Link{}, field: %Field{}}, :count),
    do: {:error, {:count_takes_no_field, spec}}

  defp build(spec, _root, %{field: %Field{} = field}, agg)
       when agg in [:sum, :avg] and field.type not in [:integer, :float, :decimal],
       do: {:error, {:aggregate_needs_number, spec}}

  defp build(spec, _root, %{field: %Field{} = field}, agg)
       when agg in [:min, :max] and field.type in [:boolean],
       do: {:error, {:aggregate_needs_ordered_value, spec}}

  defp build(spec, _root, %{table: %Table{time_field: nil}}, :latest),
    do: {:error, {:latest_needs_time_field, spec}}

  defp build(spec, root, %{many: %Link{} = many} = walk, agg) do
    field = walk.field
    links = walk.hops ++ [many] ++ walk.tail
    short = if field, do: "#{field.label} (#{agg_label(agg)})", else: agg_label(:count)

    heading =
      case field do
        nil ->
          "#{many.label} #{String.downcase(agg_label(:count))}"

        field ->
          "#{List.last(links).label} #{lower_first(field.label)} #{String.downcase(agg_label(agg))}"
      end

    {:ok,
     %__MODULE__{
       spec: spec,
       id: dom_id(spec),
       label: label(links, [], short),
       short_label: heading,
       type: rollup_type(agg, field),
       kind: :rollup,
       root: root,
       table: walk.table,
       hops: walk.hops,
       many: many,
       tail: walk.tail,
       field: field,
       agg: agg,
       sortable: true,
       depth: length(links)
     }}
  end

  defp rollup_type(:count, _field), do: :integer
  defp rollup_type(:avg, _field), do: :float
  defp rollup_type(:list, _field), do: :string
  defp rollup_type(_agg, %Field{type: type}), do: type

  defp label([], [], short), do: short
  defp label(links, _acc, short), do: Enum.map_join(links, " › ", & &1.label) <> " › " <> short

  # The heading a column scans by: a walked field carries the link it came
  # through ("Company name"), a rollup the link and the word for its
  # aggregate ("Users count"), so three counts side by side stay apart.
  defp short_label([], field_label), do: field_label
  defp short_label(hops, field_label), do: "#{List.last(hops).label} #{lower_first(field_label)}"

  # "Name" reads as "name" after a link's label; an acronym such as "SKU" keeps its case.
  defp lower_first(<<first, second, rest::binary>>) when first in ?A..?Z and second in ?a..?z,
    do: String.downcase(<<first>>) <> <<second, rest::binary>>

  defp lower_first(label), do: label

  @doc "The aggregate's word in a label."
  @spec agg_label(agg()) :: String.t()
  def agg_label(:count), do: "Count"
  def agg_label(:sum), do: "Sum"
  def agg_label(:avg), do: "Average"
  def agg_label(:min), do: "Min"
  def agg_label(:max), do: "Max"
  def agg_label(:latest), do: "Latest"
  def agg_label(:list), do: "List"

  @doc "A DOM-safe id for the spec: dots become hyphens, the colon an underscore."
  @spec dom_id(String.t()) :: String.t()
  def dom_id(spec), do: spec |> String.replace(".", "-") |> String.replace(":", "_")

  @doc "Whether the column's values order on a number line."
  @spec numeric?(t()) :: boolean()
  def numeric?(%__MODULE__{kind: :rollup, agg: agg}) when agg in [:count, :sum, :avg], do: true

  def numeric?(%__MODULE__{kind: :rollup, agg: agg, field: %Field{} = field})
      when agg in [:min, :max],
      do: Field.numeric?(field)

  def numeric?(%__MODULE__{kind: :rollup}), do: false
  def numeric?(%__MODULE__{type: type}), do: Field.numeric?(type)

  @doc "Whether the column shows a rollup a person can expand."
  @spec expandable?(t()) :: boolean()
  def expandable?(%__MODULE__{kind: :rollup}), do: true
  def expandable?(%__MODULE__{}), do: false
end
