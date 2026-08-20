defmodule Bilimbi.Core.Geonames do
  @moduledoc """
  Public lookup API for Bilimbi's geographic reference data.

  Callers use ISO and GeoNames identities without depending on Ecto schemas or
  table details. Fresh installations may return empty results until reference
  data has been imported.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Geonames.Admin1
  alias Bilimbi.Core.Geonames.Admin1Index
  alias Bilimbi.Core.Geonames.Admin1Summary
  alias Bilimbi.Core.Geonames.City
  alias Bilimbi.Core.Geonames.CitySummary
  alias Bilimbi.Core.Geonames.Country
  alias Bilimbi.Core.Geonames.CountryIndex
  alias Bilimbi.Core.Geonames.CountryOption
  alias Bilimbi.Core.Geonames.CountrySummary
  alias Bilimbi.Core.Geonames.Page
  alias Bilimbi.Core.Geonames.Postcode
  alias Bilimbi.Core.Geonames.PostcodeCountrySummary
  alias Bilimbi.Core.Geonames.PostcodeIndex
  alias Bilimbi.Core.Geonames.PostcodeOverrides
  alias Bilimbi.Core.Geonames.PostcodeSummary
  alias Bilimbi.Core.Geonames.ReferenceData

  @type import_error ::
          {:invalid_dataset, term()}
          | {:invalid_country_iso, term()}
          | {:download, atom() | {:postcodes, String.t()}, term()}
          | {:extract, atom() | {:postcodes, String.t()}, term()}
          | {:import, atom() | {:postcodes, String.t()}, term()}

  @type index_query :: map() | keyword()

  @page_sizes [25, 50, 100, 300]
  @country_sort_fields %{
    iso: :iso,
    country: :country,
    capital: :capital,
    phone: :phone,
    currency_code: :currency_code,
    population: :population,
    updated_at: :updated_at
  }
  @admin1_sort_fields %{
    country_name: :country_name,
    code: :code,
    name: :name,
    alt_name: :alt_name,
    updated_at: :updated_at
  }
  @postcode_sort_fields %{
    country_name: :country_name,
    postcode: :postcode,
    place_name: :place_name,
    admin1_code: :admin1_code,
    updated_at: :updated_at
  }
  @summary_sort_fields %{country_name: true, country_iso: true, record_count: true}
  @country_initial_directions %{population: :desc, updated_at: :desc}
  @admin1_initial_directions %{updated_at: :desc}
  @postcode_initial_directions %{updated_at: :desc}
  @summary_initial_directions %{record_count: :desc}
  @postcode_search_limit 10
  @city_search_limit 15

  @doc """
  Downloads and imports the selected canonical GeoNames datasets.

  Supported options: `:datasets`, `:postcodes`, `:cache_dir`, `:force`,
  `:ttl_days`, `:connect_timeout`, and `:receive_timeout`. Every dataset import is atomic and a
  payload that yields no valid rows is rejected with
  `{:error, {:import, dataset, :no_valid_rows}}`; a failed import restores
  the previously known-good download cache.
  """
  @spec import_reference_data(keyword()) :: {:ok, map()} | {:error, import_error()}
  def import_reference_data(opts \\ []) do
    ReferenceData.run(
      Keyword.take(opts, [
        :datasets,
        :postcodes,
        :cache_dir,
        :force,
        :ttl_days,
        :connect_timeout,
        :receive_timeout
      ])
    )
  end

  @spec list_countries() :: [CountrySummary.t()]
  def list_countries do
    from(country in Country, order_by: [asc: country.country, asc: country.iso])
    |> Repo.all()
    |> Enum.map(&CountrySummary.from_schema/1)
  end

  @doc """
  Returns a bounded, searchable, sortable page for the read-only Countries index.

  Query values may use atom or string keys. Invalid input is normalized to the
  source-compatible defaults, so caller text never becomes a query identifier.
  """
  @spec page_countries(index_query()) :: Page.t(CountryIndex.t())
  def page_countries(query \\ %{}) do
    options =
      normalize_index_query(query, @country_sort_fields, :country, @country_initial_directions)

    Country
    |> maybe_search_countries(options.search)
    |> country_page(options)
  end

  @spec get_country(String.t()) :: CountrySummary.t() | nil
  def get_country(iso) do
    with {:ok, iso} <- normalize_iso(iso),
         %Country{} = country <- Repo.get_by(Country, iso: iso) do
      CountrySummary.from_schema(country)
    else
      _other -> nil
    end
  end

  @doc """
  Updates a country's display name by its ID or ISO code.
  """
  @spec update_country_name(pos_integer() | String.t(), String.t()) ::
          {:ok, CountryIndex.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_country_name(id_or_iso, name) when is_binary(name) do
    trimmed_name = String.trim(name)

    query =
      case id_or_iso do
        id when is_integer(id) ->
          from(c in Country, where: c.id == ^id)

        iso when is_binary(iso) ->
          case Integer.parse(iso) do
            {id, ""} ->
              from(c in Country, where: c.id == ^id)

            _ ->
              case normalize_iso(iso) do
                {:ok, valid_iso} -> from(c in Country, where: c.iso == ^valid_iso)
                :error -> from(c in Country, where: false)
              end
          end
      end

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      country ->
        country
        |> Country.name_changeset(%{country: trimmed_name})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, CountryIndex.from_schema(updated)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Returns a bounded, searchable, sortable page for the read-only Admin1 index.

  The optional `country_iso` filter is normalized as an ISO code. A malformed
  filter produces no rows rather than widening the global reference query.
  """
  @spec page_admin1(index_query()) :: Page.t(Admin1Index.t())
  def page_admin1(query \\ %{}) do
    options =
      normalize_index_query(query, @admin1_sort_fields, :country_name, @admin1_initial_directions)

    Admin1
    |> admin1_with_country_name()
    |> maybe_search_admin1(options.search)
    |> maybe_filter_admin1(query_value(query_map(query), country_filter_keys(), nil))
    |> admin1_page(options)
  end

  @doc """
  Lists only countries represented by imported Admin1 divisions, ordered by name.
  """
  @spec admin1_filter_countries() :: [CountryOption.t()]
  def admin1_filter_countries do
    Admin1
    |> join(:inner, [admin1], country in Country,
      on: country.iso == fragment("split_part(?, '.', 1)", admin1.code)
    )
    |> distinct(true)
    |> order_by([_admin1, country], [{:asc, country.country}, {:asc, country.iso}])
    |> select([_admin1, country], {country.iso, country.country})
    |> Repo.all()
    |> Enum.map(fn {iso, country} -> CountryOption.new(iso, country) end)
  end

  @spec list_admin1(String.t()) :: [Admin1Summary.t()]
  def list_admin1(country_iso) do
    case normalize_iso(country_iso) do
      {:ok, iso} ->
        from(admin1 in Admin1,
          where: fragment("split_part(?, '.', 1) = ?", admin1.code, ^iso),
          order_by: [asc: admin1.name, asc: admin1.code]
        )
        |> Repo.all()
        |> Enum.map(&Admin1Summary.from_schema/1)

      :error ->
        []
    end
  end

  @doc """
  Updates an admin1 division's display name by its ID.
  """
  @spec update_admin1_name(term(), term()) ::
          {:ok, Admin1Index.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_admin1_name(id, name) when is_binary(name) do
    trimmed_name = String.trim(name)

    query =
      case id do
        int_id when is_integer(int_id) ->
          from(a in Admin1, where: a.id == ^int_id)

        str_id when is_binary(str_id) ->
          case Integer.parse(str_id) do
            {int_id, ""} -> from(a in Admin1, where: a.id == ^int_id)
            _ -> from(a in Admin1, where: false)
          end

        _ ->
          from(a in Admin1, where: false)
      end

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      admin1 ->
        country_iso =
          case String.split(admin1.code || "", ".", parts: 2) do
            [iso | _] when iso != "" -> iso
            _ -> nil
          end

        country_name =
          if country_iso do
            Repo.one(from(c in Country, where: c.iso == ^country_iso, select: c.country))
          end

        admin1
        |> Admin1.name_changeset(%{name: trimmed_name})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, Admin1Index.from_schema(updated, country_name)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  def update_admin1_name(_id, _name), do: {:error, :not_found}

  @doc """
  Returns a bounded, searchable, sortable page for the read-only Postcodes index.
  """
  @spec page_postcodes(index_query()) :: Page.t(PostcodeIndex.t())
  def page_postcodes(query \\ %{}) do
    options =
      normalize_index_query(
        query,
        @postcode_sort_fields,
        :country_name,
        @postcode_initial_directions
      )

    Postcode
    |> postcode_with_country_name()
    |> maybe_search_postcodes(options.search)
    |> postcode_page(options)
  end

  @doc """
  Lists imported-postcode totals by country for the read-only Postcodes index.

  This independent summary is deliberately unpaginated and unaffected by the
  main postcode search, because its maximum size is bounded by imported countries.
  """
  @spec list_postcode_country_summaries(index_query()) :: [PostcodeCountrySummary.t()]
  def list_postcode_country_summaries(query \\ %{}) do
    options =
      normalize_index_query(
        query,
        @summary_sort_fields,
        :country_name,
        @summary_initial_directions
      )

    from(postcode in Postcode,
      left_join: country in Country,
      on: postcode.country_iso == country.iso,
      group_by: [postcode.country_iso, country.country],
      select: %{
        country_iso: postcode.country_iso,
        country_name: country.country,
        record_count: count(postcode.id)
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      PostcodeCountrySummary.new(row.country_iso, row.country_name, row.record_count)
    end)
    |> sort_postcode_country_summaries(options)
  end

  @doc "Returns a changeset for an operator-managed postcode form."
  @spec change_postcode(map()) :: Ecto.Changeset.t()
  def change_postcode(attrs \\ %{}), do: PostcodeOverrides.changeset(attrs)

  @doc "Creates an operator-managed postcode that survives reference-data refreshes."
  @spec create_postcode(map()) ::
          {:ok, PostcodeIndex.t()} | {:error, Ecto.Changeset.t()}
  def create_postcode(attrs) do
    case PostcodeOverrides.create(attrs) do
      {:ok, {postcode, override}} -> {:ok, postcode_index(postcode, override)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Updates a postcode using the revision returned by `page_postcodes/1`."
  @spec update_postcode(term(), term(), map()) ::
          {:ok, PostcodeIndex.t()} | {:error, :not_found | :stale | Ecto.Changeset.t()}
  def update_postcode(id, expected_revision, attrs) do
    case PostcodeOverrides.update(id, expected_revision, attrs) do
      {:ok, {postcode, override}} -> {:ok, postcode_index(postcode, override)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns distinct postcode values for an Address form's country and prefix.

  The global reference-data query treats the caller's prefix literally and is
  bounded to ten values. An empty prefix returns the country's first ten
  postcodes in ascending order.
  """
  @spec search_postcodes(String.t(), String.t()) :: [String.t()]
  def search_postcodes(country_iso, prefix) do
    with {:ok, iso} <- normalize_iso(country_iso),
         {:ok, prefix} <- normalize_search_text(prefix) do
      pattern = escape_like(prefix) <> "%"

      from(entry in Postcode,
        where: entry.country_iso == ^iso and ilike(entry.postcode, ^pattern),
        select: entry.postcode,
        distinct: true,
        order_by: [asc: entry.postcode],
        limit: @postcode_search_limit
      )
      |> Repo.all()
    else
      :error -> []
    end
  end

  @doc """
  Returns city names for an Address form's country, query, and optional Admin1.

  Canonical and ASCII names use a literal prefix match, while alternate names
  use a literal contains match. The database candidate set is bounded to 15 by
  population before exact duplicate names are removed. `:admin1_code` accepts
  either the raw GeoNames value or the module's full `CC.value` identity.
  """
  @spec search_city_names(String.t(), String.t(), keyword()) :: [String.t()]
  def search_city_names(country_iso, query, opts \\ []) do
    with {:ok, iso} <- normalize_iso(country_iso),
         {:ok, query} <- normalize_search_text(query),
         {:ok, admin1_code} <- normalize_city_admin1(Keyword.get(opts, :admin1_code), iso) do
      City
      |> where([city], city.country_iso == ^iso)
      |> maybe_filter_city_admin1(admin1_code)
      |> maybe_search_cities(query)
      |> order_by([city], desc: city.population, asc: city.geoname_id)
      |> limit(@city_search_limit)
      |> select([city], city.name)
      |> Repo.all()
      |> Enum.uniq()
    else
      :error -> []
    end
  end

  @spec lookup_postcode(String.t(), String.t()) :: [PostcodeSummary.t()]
  def lookup_postcode(country_iso, postcode) do
    with {:ok, iso} <- normalize_iso(country_iso),
         {:ok, postcode} <- normalize_required(postcode) do
      from(entry in Postcode,
        where: entry.country_iso == ^iso and entry.postcode == ^postcode,
        order_by: [asc: entry.place_name, asc: entry.id]
      )
      |> Repo.all()
      |> Enum.map(&PostcodeSummary.from_schema/1)
    else
      :error -> []
    end
  end

  @spec get_city_by_geoname_id(pos_integer()) :: CitySummary.t() | nil
  def get_city_by_geoname_id(geoname_id)
      when is_integer(geoname_id) and geoname_id > 0 do
    case Repo.get_by(City, geoname_id: geoname_id) do
      nil -> nil
      city -> CitySummary.from_schema(city)
    end
  end

  def get_city_by_geoname_id(_geoname_id), do: nil

  defp country_page(query, options) do
    total_entries = Repo.aggregate(query, :count, :id)

    entries =
      query
      |> order_countries(options.sort_by, options.sort_dir)
      |> offset(^((options.page - 1) * options.page_size))
      |> limit(^options.page_size)
      |> Repo.all()
      |> Enum.map(&CountryIndex.from_schema/1)

    page(entries, options, total_entries)
  end

  defp admin1_with_country_name(query) do
    from(admin1 in query,
      left_join: country in Country,
      on: country.iso == fragment("split_part(?, '.', 1)", admin1.code)
    )
  end

  defp admin1_page(query, options) do
    total_entries = Repo.aggregate(query, :count, :id)

    entries =
      query
      |> order_admin1(options.sort_by, options.sort_dir)
      |> offset(^((options.page - 1) * options.page_size))
      |> limit(^options.page_size)
      |> select([admin1, country], {admin1, country.country})
      |> Repo.all()
      |> Enum.map(fn {admin1, country_name} -> Admin1Index.from_schema(admin1, country_name) end)

    page(entries, options, total_entries)
  end

  defp postcode_with_country_name(query) do
    from(postcode in query,
      left_join: country in Country,
      on: postcode.country_iso == country.iso
    )
  end

  defp postcode_page(query, options) do
    total_entries = Repo.aggregate(query, :count, :id)

    rows =
      query
      |> order_postcodes(options.sort_by, options.sort_dir)
      |> offset(^((options.page - 1) * options.page_size))
      |> limit(^options.page_size)
      |> select([postcode, country], {postcode, country.country})
      |> Repo.all()

    overrides = rows |> Enum.map(&elem(&1, 0)) |> PostcodeOverrides.provenance_for()

    entries =
      Enum.map(rows, fn {postcode, country_name} ->
        PostcodeIndex.from_schema(postcode, country_name, Map.get(overrides, postcode.id))
      end)

    page(entries, options, total_entries)
  end

  defp postcode_index(postcode, override) do
    country_name =
      Repo.one(
        from(country in Country,
          where: country.iso == ^postcode.country_iso,
          select: country.country
        )
      )

    PostcodeIndex.from_schema(postcode, country_name, override)
  end

  defp page(entries, options, total_entries) do
    %Page{
      entries: entries,
      page: options.page,
      page_size: options.page_size,
      total_entries: total_entries,
      total_pages: total_pages(total_entries, options.page_size)
    }
  end

  defp maybe_search_countries(query, nil), do: query

  defp maybe_search_countries(query, search) do
    pattern = "%#{search}%"

    from(country in query,
      where: ilike(country.country, ^pattern) or ilike(country.iso, ^pattern)
    )
  end

  defp maybe_search_admin1(query, nil), do: query

  defp maybe_search_admin1(query, search) do
    pattern = "%#{search}%"

    from([admin1, country] in query,
      where:
        ilike(admin1.name, ^pattern) or ilike(admin1.code, ^pattern) or
          ilike(country.country, ^pattern)
    )
  end

  defp maybe_filter_admin1(query, value) do
    case normalize_country_filter(value) do
      nil ->
        query

      :invalid ->
        from(_admin1 in query, where: false)

      iso ->
        from([admin1, _country] in query,
          where: fragment("upper(split_part(?, '.', 1)) = ?", admin1.code, ^iso)
        )
    end
  end

  defp maybe_search_postcodes(query, nil), do: query

  defp maybe_search_postcodes(query, search) do
    pattern = "%#{search}%"

    from([postcode, country] in query,
      where:
        ilike(postcode.postcode, ^pattern) or ilike(postcode.place_name, ^pattern) or
          ilike(postcode.country_iso, ^pattern) or ilike(country.country, ^pattern)
    )
  end

  defp maybe_filter_city_admin1(query, nil), do: query

  defp maybe_filter_city_admin1(query, admin1_code) do
    from(city in query, where: city.admin1_code == ^admin1_code)
  end

  defp maybe_search_cities(query, ""), do: query

  defp maybe_search_cities(query, search) do
    escaped = escape_like(search)
    prefix = escaped <> "%"
    contains = "%" <> escaped <> "%"

    from(city in query,
      where:
        ilike(city.name, ^prefix) or ilike(city.ascii_name, ^prefix) or
          ilike(city.alternate_names, ^contains)
    )
  end

  defp order_countries(query, sort_by, sort_dir) do
    sort_field = Map.fetch!(@country_sort_fields, sort_by)

    order_by(query, [country], [
      {^sort_dir, field(country, ^sort_field)},
      {:asc, country.iso}
    ])
  end

  defp order_admin1(query, :country_name, sort_dir) do
    order_by(query, [admin1, country], [{^sort_dir, country.country}, {:desc, admin1.id}])
  end

  defp order_admin1(query, sort_by, sort_dir) do
    sort_field = Map.fetch!(@admin1_sort_fields, sort_by)

    order_by(query, [admin1, _country], [
      {^sort_dir, field(admin1, ^sort_field)},
      {:desc, admin1.id}
    ])
  end

  defp order_postcodes(query, :country_name, sort_dir) do
    order_by(query, [postcode, country], [{^sort_dir, country.country}, {:desc, postcode.id}])
  end

  defp order_postcodes(query, sort_by, sort_dir) do
    sort_field = Map.fetch!(@postcode_sort_fields, sort_by)

    order_by(query, [postcode, _country], [
      {^sort_dir, field(postcode, ^sort_field)},
      {:desc, postcode.id}
    ])
  end

  defp sort_postcode_country_summaries(summaries, options) do
    Enum.sort(summaries, fn left, right ->
      comparison =
        left
        |> summary_sort_value(options.sort_by)
        |> compare_summary_values(summary_sort_value(right, options.sort_by))

      case comparison do
        :eq -> left.country_iso <= right.country_iso
        :lt -> options.sort_dir == :asc
        :gt -> options.sort_dir == :desc
      end
    end)
  end

  defp summary_sort_value(summary, :country_name), do: summary.country_name
  defp summary_sort_value(summary, :country_iso), do: summary.country_iso
  defp summary_sort_value(summary, :record_count), do: summary.record_count

  defp compare_summary_values(left, right) when left < right, do: :lt
  defp compare_summary_values(left, right) when left > right, do: :gt
  defp compare_summary_values(_left, _right), do: :eq

  defp normalize_index_query(query, sort_fields, default_sort, initial_directions) do
    query = query_map(query)
    sort_by = normalize_sort(query_value(query, sort_keys(), nil), sort_fields, default_sort)

    %{
      page: normalize_positive_integer(query_value(query, page_keys(), 1), 1),
      page_size: normalize_page_size(query_value(query, page_size_keys(), @page_sizes |> hd())),
      search: normalize_search(query_value(query, search_keys(), nil)),
      sort_by: sort_by,
      sort_dir:
        normalize_sort_direction(
          query_value(query, sort_direction_keys(), nil),
          sort_by,
          initial_directions
        )
    }
  end

  defp query_map(query) when is_map(query), do: query

  defp query_map(query) when is_list(query) do
    if Keyword.keyword?(query), do: Map.new(query), else: %{}
  end

  defp query_map(_query), do: %{}

  defp query_value(query, keys, default) do
    Enum.reduce_while(keys, default, fn key, _value ->
      case Map.fetch(query, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, default}
      end
    end)
  end

  defp page_keys, do: [:page, "page"]

  defp page_size_keys do
    [:page_size, "page_size", :per_page, "per_page", :perPage, "perPage"]
  end

  defp search_keys, do: [:search, "search"]
  defp sort_keys, do: [:sort_by, "sort_by", :sortBy, "sortBy", :sort, "sort"]

  defp sort_direction_keys do
    [:sort_dir, "sort_dir", :sortDir, "sortDir", :direction, "direction"]
  end

  defp country_filter_keys do
    [
      :country_iso,
      "country_iso",
      :filter_country_iso,
      "filter_country_iso",
      :filterCountryIso,
      "filterCountryIso"
    ]
  end

  defp normalize_search(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      search -> search
    end
  end

  defp normalize_search(_value), do: nil

  defp normalize_sort(value, sort_fields, default_sort) when is_atom(value) do
    if Map.has_key?(sort_fields, value), do: value, else: default_sort
  end

  defp normalize_sort(value, sort_fields, default_sort) when is_binary(value) do
    Enum.find(Map.keys(sort_fields), default_sort, &(Atom.to_string(&1) == value))
  end

  defp normalize_sort(_value, _sort_fields, default_sort), do: default_sort

  defp normalize_sort_direction(value, sort_by, initial_directions) do
    case value do
      :asc -> :asc
      "asc" -> :asc
      :desc -> :desc
      "desc" -> :desc
      _other -> Map.get(initial_directions, sort_by, :asc)
    end
  end

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _other -> default
    end
  end

  defp normalize_positive_integer(_value, default), do: default

  defp normalize_page_size(value) do
    value = normalize_positive_integer(value, hd(@page_sizes))
    Enum.find(@page_sizes, List.last(@page_sizes), &(&1 >= value))
  end

  defp normalize_country_filter(nil), do: nil

  defp normalize_country_filter(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      _country_iso -> normalize_country_iso(value)
    end
  end

  defp normalize_country_filter(_value), do: :invalid

  defp normalize_country_iso(value) do
    case normalize_iso(value) do
      {:ok, iso} -> iso
      :error -> :invalid
    end
  end

  defp normalize_search_text(value) when is_binary(value), do: {:ok, String.trim(value)}
  defp normalize_search_text(_value), do: :error

  defp normalize_city_admin1(nil, _iso), do: {:ok, nil}

  defp normalize_city_admin1(value, iso) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:ok, nil}

      code ->
        normalize_city_admin1_code(String.split(code, ".", parts: 2), iso)
    end
  end

  defp normalize_city_admin1(_value, _iso), do: :error

  defp normalize_city_admin1_code([raw_code], _iso),
    do: {:ok, String.upcase(raw_code)}

  defp normalize_city_admin1_code([country_iso, raw_code], iso) when raw_code != "" do
    if String.upcase(country_iso) == iso do
      {:ok, String.upcase(raw_code)}
    else
      :error
    end
  end

  defp normalize_city_admin1_code(_parts, _iso), do: :error

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp total_pages(0, _page_size), do: 0
  defp total_pages(total_entries, page_size), do: div(total_entries + page_size - 1, page_size)

  defp normalize_iso(value) do
    case normalize_required(value) do
      {:ok, iso} when byte_size(iso) == 2 ->
        if String.match?(iso, ~r/\A[A-Za-z]{2}\z/), do: {:ok, String.upcase(iso)}, else: :error

      _other ->
        :error
    end
  end

  defp normalize_required(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :error
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_required(_value), do: :error
end
