defmodule Bilimbi.Core.Company.AdministrationIndex do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.AdministrationEntry
  alias Bilimbi.Core.Company.AdministrationPage
  alias Bilimbi.Core.Company.Schema

  @default_page 1
  @default_page_size 25
  @max_page_size 300
  @statuses Schema.statuses()
  @allowed_option_keys [:page, :page_size, :search, :status_filter, :sort_by, :sort_dir]

  @type normalized_options :: %{
          page: pos_integer(),
          page_size: pos_integer(),
          search: String.t(),
          status_filter: :all | String.t(),
          sort_by: :name | :status | :jurisdiction,
          sort_dir: :asc | :desc
        }

  @spec normalize_options(keyword()) :: {:ok, normalized_options()} | {:error, :invalid_options}
  def normalize_options(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- unique_keys?(options),
         true <- Enum.all?(Keyword.keys(options), &(&1 in @allowed_option_keys)),
         {:ok, page} <- positive_integer(Keyword.get(options, :page, @default_page)),
         {:ok, page_size} <- page_size(Keyword.get(options, :page_size, @default_page_size)),
         {:ok, search} <- search(Keyword.get(options, :search, "")),
         {:ok, status_filter} <- status_filter(Keyword.get(options, :status_filter, :all)),
         {:ok, sort_by} <- sort_by(Keyword.get(options, :sort_by, :name)),
         {:ok, sort_dir} <- sort_dir(Keyword.get(options, :sort_dir, :asc)) do
      {:ok,
       %{
         page: page,
         page_size: page_size,
         search: search,
         status_filter: status_filter,
         sort_by: sort_by,
         sort_dir: sort_dir
       }}
    else
      _ -> {:error, :invalid_options}
    end
  end

  def normalize_options(_options), do: {:error, :invalid_options}

  @spec page(Scope.t(), normalized_options()) :: AdministrationPage.t()
  def page(%Scope{} = scope, options) do
    query =
      scope
      |> base_query()
      |> apply_search(options.search)
      |> apply_status_filter(options.status_filter)

    total_entries = query |> exclude(:order_by) |> Repo.aggregate(:count, :id)
    total_pages = page_count(total_entries, options.page_size)

    entries =
      query
      |> apply_order(options.sort_by, options.sort_dir)
      |> offset(^((options.page - 1) * options.page_size))
      |> limit(^options.page_size)
      |> select(
        [company, parent, primary],
        {company, parent.name, not is_nil(primary.company_id)}
      )
      |> Repo.all()
      |> Enum.map(&AdministrationEntry.from_query_result/1)

    %AdministrationPage{
      entries: entries,
      page: options.page,
      page_size: options.page_size,
      total_entries: total_entries,
      total_pages: total_pages,
      has_prev?: options.page > 1,
      has_next?: options.page < total_pages
    }
  end

  # The parent join stays inside the same tenant by construction: a parent_id
  # can only reference a company row, and every company row carries this
  # tenant's id through the scoped base query on the child side.
  defp base_query(scope) do
    tenant_id = Scope.tenant_id(scope)

    from company in Tenancy.scope_query(Schema, scope),
      left_join: parent in Schema,
      on: parent.id == company.parent_id and is_nil(parent.deleted_at),
      left_join: primary in "tenant_primary_companies",
      on: primary.tenant_id == ^tenant_id and primary.company_id == company.id,
      where: is_nil(company.deleted_at)
  end

  defp apply_search(query, ""), do: query

  defp apply_search(query, search) do
    pattern = "%#{escape_like(search)}%"

    where(
      query,
      [company, _parent, _primary],
      fragment("? ILIKE ? ESCAPE E'\\\\'", company.name, ^pattern) or
        fragment("? ILIKE ? ESCAPE E'\\\\'", company.code, ^pattern) or
        fragment("? ILIKE ? ESCAPE E'\\\\'", company.legal_name, ^pattern) or
        fragment("? ILIKE ? ESCAPE E'\\\\'", company.email, ^pattern) or
        fragment("? ILIKE ? ESCAPE E'\\\\'", company.jurisdiction, ^pattern)
    )
  end

  defp apply_status_filter(query, :all), do: query

  defp apply_status_filter(query, status),
    do: where(query, [company, _parent, _primary], company.status == ^status)

  defp apply_order(query, :name, :asc),
    do: order_by(query, [company, _parent, _primary], asc: company.name, desc: company.id)

  defp apply_order(query, :name, :desc),
    do: order_by(query, [company, _parent, _primary], desc: company.name, desc: company.id)

  defp apply_order(query, :status, :asc),
    do: order_by(query, [company, _parent, _primary], asc: company.status, desc: company.id)

  defp apply_order(query, :status, :desc),
    do: order_by(query, [company, _parent, _primary], desc: company.status, desc: company.id)

  defp apply_order(query, :jurisdiction, :asc),
    do: order_by(query, [company, _parent, _primary], asc: company.jurisdiction, desc: company.id)

  defp apply_order(query, :jurisdiction, :desc),
    do:
      order_by(query, [company, _parent, _primary], desc: company.jurisdiction, desc: company.id)

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_value), do: :error

  defp page_size(value) when is_integer(value) and value in 1..@max_page_size, do: {:ok, value}
  defp page_size(_value), do: :error

  defp search(nil), do: {:ok, ""}
  defp search(value) when is_binary(value), do: {:ok, value}
  defp search(_value), do: :error

  defp status_filter(:all), do: {:ok, :all}
  defp status_filter(value) when value in @statuses, do: {:ok, value}
  defp status_filter(_value), do: :error

  defp sort_by(value) when value in [:name, :status, :jurisdiction], do: {:ok, value}
  defp sort_by(_value), do: :error

  defp sort_dir(value) when value in [:asc, :desc], do: {:ok, value}
  defp sort_dir(_value), do: :error

  defp unique_keys?(options),
    do: options |> Keyword.keys() |> Enum.uniq() |> length() == length(options)

  defp page_count(0, _page_size), do: 0
  defp page_count(total_entries, page_size), do: div(total_entries + page_size - 1, page_size)

  defp escape_like(search) do
    search
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
