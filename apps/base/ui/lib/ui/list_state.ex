defmodule Bilimbi.Base.UI.ListState do
  @moduledoc """
  URL state for an operational list: page, page size, search, sort, and the
  page's own filters.

  `<.filter_toolbar>` and `<.pagination>` render the controls. This module
  parses the query string, patches it back, and turns a header click into the
  next sort. A private `state_from_params`, `to_int`, `nilify`, or
  `positive_integer` is the copy this replaced. Build a spec with `spec!/1`
  and keep that page's current URL keys in it: a key rename breaks links
  people have already sent.

  The struct fields a page reads are `search`, `page`, `page_size`,
  `sort_by`, `sort_dir`, and `filters`. `filters` holds each extra filter
  under the atom named in the spec. Sort columns are atoms from the spec,
  never from `String.to_atom/1` on the query string.

  ## What the spec decides

    * `sortable` maps each allowed column to the direction a new click on
      that column uses, and the direction a URL uses when `sort_dir` is
      missing or unrecognised. `default_sort` is the column an unrecognised
      `sort_by` becomes. Omit `sortable` on a list that does not sort.
    * `page_size_param` is the query key (`"page_size"` or `"per_page"`).
      The toolbar and `<.pagination>` always post `perPage`; that form key
      is not the query key. `page_size_aliases` are extra inbound keys, used
      only when `page_size_param` itself is absent.
    * `invalid_page_size` is `:keep` (an unrecognised posted size leaves the
      current size) or `:default` (it falls back to `default_page_size`).
      A missing `perPage` always keeps the current size. An unrecognised
      size in the URL always falls back to `default_page_size`.
    * `filters` normalises each extra query key. `{:one_of, allowed, default}`
      keeps a binary in `allowed` and otherwise uses `default`.
      `{:string, default}` keeps any binary. `{:string, default, rewrite}`
      maps a binary through `rewrite` first (`%{"all" => ""}` is how Menu
      Inspector treats `source=all`). A missing form key keeps the current
      value; a missing query key uses `default`. The spec is plain data so a
      page can hold it in a module attribute.
    * `param_prefix` is written before every query key, inbound and
      outbound, so two lists share one URL (`"users_"` gives
      `users_search`, `users_page`, `users_per_page`). `param_names` renames
      the four fixed keys (`:search`, `:page`, `:sort_by`, `:sort_dir`)
      before the prefix, for a page whose links already use another name.
    * `omit_defaults: true` leaves out of `to_params/1` a value the URL
      would parse back to the same thing (page 1, the default sort and
      direction, the default page size, a default filter, a blank search),
      so a second list's defaults do not clutter the first's URL.
    * `omit_blank` lists keys (`:search` or a filter name) left out of the
      query when the value is `""`. Every other page writes the empty value
      so a shared link round-trips.

  `clamp_to_last_page/3` moves a page past the end back onto the last real
  page. The page decides whether to query again in place or `push_patch`
  the corrected URL. Pass `empty: :reset` when an empty result on a page
  after the first should return to page 1; the default leaves that page
  number where the URL put it.

  `paginate/2` pages rows a panel already holds in memory, for a list the
  page does not query by page. The panel filters and sorts; this owns the
  slice, the last-page clamp, and the counts `<.pagination>` reads.

  `Bilimbi.Base.UI.Params` is the integer and blank coercion underneath.
  """

  alias Bilimbi.Base.UI.Params

  @enforce_keys [:search, :page, :page_size, :sort_by, :sort_dir, :filters, :spec]
  defstruct [:search, :page, :page_size, :sort_by, :sort_dir, :filters, :spec]

  @type sort_dir :: :asc | :desc
  @type filter_value :: String.t()

  @type t :: %__MODULE__{
          search: String.t(),
          page: pos_integer(),
          page_size: pos_integer(),
          sort_by: atom() | nil,
          sort_dir: sort_dir() | nil,
          filters: %{optional(atom()) => filter_value()},
          spec: map()
        }

  @param_names %{search: "search", page: "page", sort_by: "sort_by", sort_dir: "sort_dir"}

  @spec_keys ~w(
    sortable
    default_sort
    page_sizes
    default_page_size
    page_size_param
    page_size_aliases
    invalid_page_size
    filters
    omit_blank
    param_prefix
    param_names
    omit_defaults
  )a

  @doc """
  Normalises a list spec. Raises `ArgumentError` when a required option is
  missing or a value is outside the vocabulary above.
  """
  @spec spec!(keyword()) :: map()
  def spec!(opts) when is_list(opts) do
    unknown = Keyword.keys(opts) -- @spec_keys

    if unknown != [] do
      raise ArgumentError, "unknown ListState spec keys: #{inspect(unknown)}"
    end

    sortable = normalize_sortable(Keyword.get(opts, :sortable))
    default_sort = Keyword.get(opts, :default_sort)

    page_sizes =
      Keyword.get(opts, :page_sizes) ||
        raise(ArgumentError, "page_sizes is required")

    default_page_size =
      Keyword.get(opts, :default_page_size) ||
        raise(ArgumentError, "default_page_size is required")

    page_size_param = Keyword.get(opts, :page_size_param, "page_size")
    page_size_aliases = Keyword.get(opts, :page_size_aliases, [])
    invalid_page_size = Keyword.get(opts, :invalid_page_size, :keep)
    filters = normalize_filters(Keyword.get(opts, :filters, []))
    omit_blank = Keyword.get(opts, :omit_blank, [])
    param_prefix = Keyword.get(opts, :param_prefix, "")
    param_names = Keyword.get(opts, :param_names, %{})
    omit_defaults = Keyword.get(opts, :omit_defaults, false)

    validate_param_keys!(param_prefix, param_names, omit_defaults)
    validate_sort!(sortable, default_sort)
    validate_page_sizes!(page_sizes, default_page_size)
    validate_page_size_param!(page_size_param, page_size_aliases, invalid_page_size)
    validate_omit_blank!(omit_blank, filters)

    %{
      sortable: sortable,
      default_sort: default_sort,
      page_sizes: page_sizes,
      default_page_size: default_page_size,
      page_size_param: page_size_param,
      page_size_aliases: page_size_aliases,
      invalid_page_size: invalid_page_size,
      filters: filters,
      omit_blank: omit_blank,
      param_prefix: param_prefix,
      param_names: Map.merge(@param_names, param_names),
      omit_defaults: omit_defaults
    }
  end

  @doc """
  The list state carried by `params`, with anything unrecognised replaced by
  the spec's default. Does not raise on a forged query string.
  """
  @spec parse(map(), map()) :: t()
  def parse(params, spec) when is_map(params) and is_map(spec) do
    sort_by = sort_by_from(Map.get(params, key(spec, :sort_by)), spec)
    sort_dir = sort_dir_from(Map.get(params, key(spec, :sort_dir)), sort_by, spec)

    %__MODULE__{
      search: string_or(Map.get(params, key(spec, :search), ""), ""),
      page: Params.positive_integer(Map.get(params, key(spec, :page)), 1),
      page_size: page_size_from_url(params, spec),
      sort_by: sort_by,
      sort_dir: sort_dir,
      filters: filters_from_url(params, spec),
      spec: spec
    }
  end

  @doc """
  Query params for `state`, using the keys recorded in its spec.

  Values are strings and integers. Blank keys named in `omit_blank` are left
  out, and so is a value `omit_defaults` says the URL parses back to the same
  thing; every other key is written, including `""`.
  """
  @spec to_params(t()) :: %{optional(String.t()) => String.t() | pos_integer()}
  def to_params(%__MODULE__{} = state) do
    spec = state.spec

    %{}
    |> maybe_put(key(spec, :page), state.page, spec.omit_defaults and state.page == 1)
    |> maybe_put(
      prefixed(spec, spec.page_size_param),
      state.page_size,
      spec.omit_defaults and state.page_size == spec.default_page_size
    )
    |> maybe_put_sort(state)
    |> maybe_put(
      key(spec, :search),
      state.search,
      state.search in [nil, ""] and (spec.omit_defaults or :search in spec.omit_blank)
    )
    |> put_filters(state)
  end

  @doc """
  Applies a toolbar or page-size submission.

  A key the form did not post keeps its current value. The page returns to 1.
  `perPage` is the form field `<.pagination>` posts; the query key stays
  whatever the spec named.
  """
  @spec apply_filters(t(), map()) :: t()
  def apply_filters(%__MODULE__{} = state, filters) when is_map(filters) do
    %{
      state
      | search: posted_string(filters, "search", state.search),
        page_size: page_size_from_form(state, Map.get(filters, "perPage")),
        page: 1,
        filters: filters_from_form(state, filters)
    }
  end

  def apply_filters(%__MODULE__{} = state, _filters), do: %{state | page: 1}

  @doc """
  The state after a header click on `column`.

  An unknown column returns `state` unchanged, so the page does not patch.
  A new column takes that column's default direction and returns to page 1.
  The same column flips between `:asc` and `:desc`.
  """
  @spec next_sort(t(), term()) :: t()
  def next_sort(%__MODULE__{spec: %{sortable: sortable}} = state, column)
      when is_binary(column) and is_map(sortable) do
    case column_atom(sortable, column) do
      nil ->
        state

      sort_by ->
        direction =
          cond do
            state.sort_by != sort_by -> Map.fetch!(sortable, sort_by)
            state.sort_dir == :asc -> :desc
            true -> :asc
          end

        %{state | sort_by: sort_by, sort_dir: direction, page: 1}
    end
  end

  def next_sort(%__MODULE__{} = state, _column), do: state

  @doc """
  Sets `page` from a pager submission. An unrecognised value becomes page 1.
  """
  @spec put_page(t(), term()) :: t()
  def put_page(%__MODULE__{} = state, page) do
    %{state | page: Params.positive_integer(page, 1)}
  end

  @doc """
  The toolbar form: `search`, `perPage`, and each extra filter.

  `<.pagination>` reads `perPage`. Filter atoms become string field names.
  """
  @spec filters_form(t(), keyword()) :: Phoenix.HTML.Form.t()
  def filters_form(%__MODULE__{} = state, opts \\ []) do
    fields =
      Map.new(state.filters, fn {key, value} -> {Atom.to_string(key), value} end)

    Phoenix.Component.to_form(
      Map.merge(fields, %{
        "search" => state.search,
        "perPage" => Integer.to_string(state.page_size)
      }),
      as: Keyword.get(opts, :as, :filters)
    )
  end

  @doc """
  When `page` is past `total_pages`, returns `state` moved to that last page.

  `page_result` is whatever the list query returned, or a map with
  `total_pages`. `empty: :reset` also moves page 2 or later back to 1 when
  there are no pages; the default `:keep` leaves the page number alone.
  """
  @spec clamp_to_last_page(t(), map(), keyword()) :: t()
  def clamp_to_last_page(state, page_result, opts \\ [])

  def clamp_to_last_page(%__MODULE__{page: page} = state, %{total_pages: total}, _opts)
      when is_integer(total) and total > 0 and page > total do
    %{state | page: total}
  end

  def clamp_to_last_page(%__MODULE__{page: page} = state, %{total_pages: 0}, opts)
      when page > 1 and is_list(opts) do
    if Keyword.get(opts, :empty, :keep) == :reset do
      %{state | page: 1}
    else
      state
    end
  end

  def clamp_to_last_page(%__MODULE__{} = state, _page_result, _opts), do: state

  @doc """
  One page of `rows` the caller already filtered and sorted, in the shape
  `<.pagination>` reads. A page past the end is clamped to the last real
  page; no rows is page 1 of zero pages.
  """
  @spec paginate([term()], t()) :: %{
          entries: [term()],
          page: pos_integer(),
          page_size: pos_integer(),
          total_entries: non_neg_integer(),
          total_pages: non_neg_integer(),
          has_prev?: boolean(),
          has_next?: boolean()
        }
  def paginate(rows, %__MODULE__{page_size: page_size} = state) when is_list(rows) do
    total_entries = length(rows)
    total_pages = ceil(total_entries / page_size)
    page = if total_pages == 0, do: 1, else: min(max(state.page, 1), total_pages)

    %{
      entries: Enum.slice(rows, (page - 1) * page_size, page_size),
      page: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages,
      has_prev?: total_pages > 0 and page > 1,
      has_next?: total_pages > 0 and page < total_pages
    }
  end

  defp normalize_sortable(nil), do: nil

  defp normalize_sortable(sortable) when is_map(sortable) and map_size(sortable) > 0 do
    Enum.each(sortable, fn
      {column, direction} when is_atom(column) and direction in [:asc, :desc] ->
        :ok

      other ->
        raise ArgumentError,
              "sortable entries are column => :asc | :desc, got: #{inspect(other)}"
    end)

    sortable
  end

  defp normalize_sortable(other) do
    raise ArgumentError,
          "sortable is a column => direction map, or omitted, got: #{inspect(other)}"
  end

  defp validate_sort!(nil, nil), do: :ok

  defp validate_sort!(nil, default_sort) do
    raise ArgumentError,
          "default_sort requires sortable, got default_sort: #{inspect(default_sort)}"
  end

  defp validate_sort!(sortable, default_sort) when is_map_key(sortable, default_sort), do: :ok

  defp validate_sort!(_sortable, default_sort) do
    raise ArgumentError, "default_sort must be one of sortable, got: #{inspect(default_sort)}"
  end

  defp validate_page_sizes!(page_sizes, default_page_size) when is_list(page_sizes) do
    unless Enum.all?(page_sizes, &(is_integer(&1) and &1 > 0)) do
      raise ArgumentError, "page_sizes must be positive integers, got: #{inspect(page_sizes)}"
    end

    unless default_page_size in page_sizes do
      raise ArgumentError,
            "default_page_size must be one of page_sizes, got: #{inspect(default_page_size)}"
    end
  end

  defp validate_page_sizes!(page_sizes, _default_page_size) do
    raise ArgumentError, "page_sizes must be a list, got: #{inspect(page_sizes)}"
  end

  defp validate_page_size_param!(param, aliases, invalid)
       when is_binary(param) and is_list(aliases) and invalid in [:keep, :default] do
    unless Enum.all?(aliases, &is_binary/1) do
      raise ArgumentError, "page_size_aliases must be strings, got: #{inspect(aliases)}"
    end

    :ok
  end

  defp validate_page_size_param!(param, aliases, invalid) do
    raise ArgumentError,
          "page_size_param, page_size_aliases, or invalid_page_size is wrong: " <>
            "#{inspect({param, aliases, invalid})}"
  end

  defp validate_param_keys!(prefix, names, omit_defaults)
       when is_binary(prefix) and is_map(names) and is_boolean(omit_defaults) do
    unless Enum.all?(names, fn {key, name} ->
             key in Map.keys(@param_names) and is_binary(name)
           end) do
      raise ArgumentError,
            "param_names renames #{inspect(Map.keys(@param_names))} to strings, got: #{inspect(names)}"
    end
  end

  defp validate_param_keys!(prefix, names, omit_defaults) do
    raise ArgumentError,
          "param_prefix is a string, param_names a map, omit_defaults a boolean, got: " <>
            inspect({prefix, names, omit_defaults})
  end

  defp validate_omit_blank!(keys, filters) when is_list(keys) do
    allowed = [:search | Map.keys(filters)]

    case keys -- allowed do
      [] -> :ok
      unknown -> raise ArgumentError, "omit_blank names unknown keys: #{inspect(unknown)}"
    end
  end

  defp validate_omit_blank!(keys, _filters) do
    raise ArgumentError, "omit_blank must be a list of keys, got: #{inspect(keys)}"
  end

  defp normalize_filters(filters) when is_list(filters) do
    Map.new(filters, fn {name, filter} ->
      unless is_atom(name),
        do: raise(ArgumentError, "filter names are atoms, got: #{inspect(name)}")

      {name, normalize_filter(filter)}
    end)
  end

  defp normalize_filters(filters) do
    raise ArgumentError, "filters must be a keyword list, got: #{inspect(filters)}"
  end

  defp normalize_filter({:one_of, allowed, default})
       when is_list(allowed) and is_binary(default) do
    unless Enum.all?(allowed, &is_binary/1) do
      raise ArgumentError, "one_of values must be strings, got: #{inspect(allowed)}"
    end

    %{kind: :one_of, allowed: allowed, rewrite: %{}, default: default, omit_blank: false}
  end

  defp normalize_filter({:string, default}) when is_binary(default) do
    %{kind: :string, allowed: [], rewrite: %{}, default: default, omit_blank: false}
  end

  defp normalize_filter({:string, default, rewrite})
       when is_binary(default) and is_map(rewrite) do
    unless Enum.all?(rewrite, fn {from, to} -> is_binary(from) and is_binary(to) end) do
      raise ArgumentError, "a string rewrite maps strings to strings, got: #{inspect(rewrite)}"
    end

    %{kind: :string, allowed: [], rewrite: rewrite, default: default, omit_blank: false}
  end

  defp normalize_filter(other) do
    raise ArgumentError,
          "a filter is {:one_of, allowed, default} or {:string, default} or " <>
            "{:string, default, rewrite}, got: #{inspect(other)}"
  end

  defp parse_filter(filter, value) when is_binary(value) do
    accept_filter(filter, Map.get(filter.rewrite, value, value))
  end

  defp parse_filter(filter, _value), do: filter.default

  defp form_filter(%{kind: :one_of} = filter, value, _current), do: parse_filter(filter, value)

  defp form_filter(filter, value, _current) when is_binary(value) do
    accept_filter(filter, Map.get(filter.rewrite, value, value))
  end

  defp form_filter(_filter, _value, current), do: current

  defp accept_filter(%{kind: :one_of, allowed: allowed, default: default}, value) do
    if value in allowed, do: value, else: default
  end

  defp accept_filter(%{kind: :string}, value), do: value

  defp sort_by_from(_value, %{sortable: nil} = spec), do: spec.default_sort

  defp sort_by_from(value, %{sortable: sortable, default_sort: default}) when is_binary(value) do
    case column_atom(sortable, value) do
      nil -> default
      column -> column
    end
  end

  defp sort_by_from(_value, %{default_sort: default}), do: default

  defp sort_dir_from(_value, nil, _spec), do: nil
  defp sort_dir_from("asc", _sort_by, _spec), do: :asc
  defp sort_dir_from("desc", _sort_by, _spec), do: :desc

  defp sort_dir_from(_value, sort_by, %{sortable: sortable}) do
    Map.fetch!(sortable, sort_by)
  end

  defp column_atom(sortable, value) do
    Enum.find_value(sortable, fn {column, _direction} ->
      if Atom.to_string(column) == value, do: column
    end)
  end

  defp page_size_from_url(params, spec) do
    raw =
      case Map.get(params, prefixed(spec, spec.page_size_param)) do
        nil -> alias_page_size(params, Enum.map(spec.page_size_aliases, &prefixed(spec, &1)))
        value -> value
      end

    accept_page_size(raw, spec.default_page_size, spec)
  end

  defp alias_page_size(_params, []), do: nil

  defp alias_page_size(params, [key | rest]) do
    case Map.get(params, key) do
      nil -> alias_page_size(params, rest)
      value -> value
    end
  end

  defp page_size_from_form(%{page_size: current}, nil), do: current

  defp page_size_from_form(%{page_size: current, spec: spec}, value) do
    fallback =
      case spec.invalid_page_size do
        :default -> spec.default_page_size
        :keep -> current
      end

    accept_page_size(value, fallback, spec)
  end

  defp accept_page_size(value, fallback, spec) do
    parsed = Params.positive_integer(value, fallback)
    if parsed in spec.page_sizes, do: parsed, else: fallback
  end

  defp filters_from_url(params, spec) do
    Map.new(spec.filters, fn {name, filter} ->
      {name, parse_filter(filter, Map.get(params, prefixed(spec, Atom.to_string(name))))}
    end)
  end

  defp filters_from_form(state, posted) do
    Map.new(state.spec.filters, fn {name, filter} ->
      current = Map.get(state.filters, name, filter.default)
      param = Atom.to_string(name)

      value =
        if Map.has_key?(posted, param) do
          form_filter(filter, Map.get(posted, param), current)
        else
          current
        end

      {name, value}
    end)
  end

  defp posted_string(filters, key, current) do
    case Map.fetch(filters, key) do
      {:ok, value} when is_binary(value) -> value
      {:ok, _} -> current
      :error -> current
    end
  end

  defp string_or(value, _fallback) when is_binary(value), do: value
  defp string_or(_value, fallback), do: fallback

  defp maybe_put_sort(params, %{spec: %{sortable: nil}}), do: params

  defp maybe_put_sort(params, %{spec: spec} = state) do
    omit = spec.omit_defaults

    params
    |> maybe_put(
      key(spec, :sort_by),
      Atom.to_string(state.sort_by),
      omit and state.sort_by == spec.default_sort
    )
    |> maybe_put(
      key(spec, :sort_dir),
      Atom.to_string(state.sort_dir),
      omit and state.sort_dir == Map.fetch!(spec.sortable, state.sort_by)
    )
  end

  defp key(spec, name), do: prefixed(spec, Map.fetch!(spec.param_names, name))
  defp prefixed(spec, name), do: spec.param_prefix <> name

  defp maybe_put(params, _key, _value, true), do: params
  defp maybe_put(params, key, value, _omit), do: Map.put(params, key, value)

  defp put_filters(params, state) do
    Enum.reduce(state.filters, params, fn {name, value}, acc ->
      filter = Map.fetch!(state.spec.filters, name)
      spec = state.spec

      omit =
        (value == "" and (name in spec.omit_blank or filter.omit_blank)) or
          (spec.omit_defaults and value == filter.default)

      maybe_put(acc, prefixed(spec, Atom.to_string(name)), value, omit)
    end)
  end
end
