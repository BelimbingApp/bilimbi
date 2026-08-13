defmodule Bilimbi.Core.Employee.AdministrationIndex do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Employee.AdministrationEntry
  alias Bilimbi.Core.Employee.AdministrationPage
  alias Bilimbi.Core.Employee.EmployeeType
  alias Bilimbi.Core.Employee.Schema

  @default_page 1
  @default_page_size 15
  @max_page_size 100
  @allowed_option_keys [:page, :page_size, :search, :type_filter, :sort_by, :sort_dir]

  @type normalized_options :: %{
          page: pos_integer(),
          page_size: pos_integer(),
          search: String.t(),
          type_filter: :all | :human | :agent,
          sort_by: :full_name | :employee_type_label | :status,
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
         {:ok, type_filter} <- type_filter(Keyword.get(options, :type_filter, :all)),
         {:ok, sort_by} <- sort_by(Keyword.get(options, :sort_by, :full_name)),
         {:ok, sort_dir} <- sort_dir(Keyword.get(options, :sort_dir, :asc)) do
      {:ok,
       %{
         page: page,
         page_size: page_size,
         search: search,
         type_filter: type_filter,
         sort_by: sort_by,
         sort_dir: sort_dir
       }}
    else
      _ -> {:error, :invalid_options}
    end
  end

  def normalize_options(_options), do: {:error, :invalid_options}

  @spec page(pos_integer(), normalized_options()) :: AdministrationPage.t()
  def page(company_id, options) do
    query = company_id |> base_query() |> apply_search(options.search) |> apply_type_filter(options.type_filter)
    total_entries = query |> exclude(:order_by) |> Repo.aggregate(:count, :id)
    total_pages = page_count(total_entries, options.page_size)

    entries =
      query
      |> apply_order(options.sort_by, options.sort_dir)
      |> offset(^((options.page - 1) * options.page_size))
      |> limit(^options.page_size)
      |> select([employee, employee_type], {employee, employee_type.label})
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

  defp base_query(company_id) do
    from employee in Schema,
      left_join: employee_type in EmployeeType,
      on: employee_type.code == employee.employee_type,
      where: employee.company_id == ^company_id
  end

  defp apply_search(query, ""), do: query

  defp apply_search(query, search) do
    pattern = "%#{escape_like(search)}%"

    where(query, [employee, _employee_type],
      fragment("? ILIKE ? ESCAPE E'\\\\'", employee.full_name, ^pattern) or
        fragment("? ILIKE ? ESCAPE E'\\\\'", employee.short_name, ^pattern) or
        fragment("? ILIKE ? ESCAPE E'\\\\'", employee.employee_number, ^pattern) or
        fragment("? ILIKE ? ESCAPE E'\\\\'", employee.email, ^pattern) or
        fragment("? ILIKE ? ESCAPE E'\\\\'", employee.designation, ^pattern) or
        fragment("? ILIKE ? ESCAPE E'\\\\'", employee.job_description, ^pattern)
    )
  end

  defp apply_type_filter(query, :all), do: query
  defp apply_type_filter(query, :agent), do: where(query, [employee, _employee_type], employee.employee_type == "agent")

  defp apply_type_filter(query, :human),
    do: where(query, [employee, _employee_type], employee.employee_type != "agent")

  defp apply_order(query, :full_name, :asc),
    do: order_by(query, [employee, _employee_type], asc: employee.full_name, desc: employee.id)

  defp apply_order(query, :full_name, :desc),
    do: order_by(query, [employee, _employee_type], desc: employee.full_name, desc: employee.id)

  defp apply_order(query, :employee_type_label, :asc),
    do: order_by(query, [employee, employee_type], asc: employee_type.label, desc: employee.id)

  defp apply_order(query, :employee_type_label, :desc),
    do: order_by(query, [employee, employee_type], desc: employee_type.label, desc: employee.id)

  defp apply_order(query, :status, :asc),
    do: order_by(query, [employee, _employee_type], asc: employee.status, desc: employee.id)

  defp apply_order(query, :status, :desc),
    do: order_by(query, [employee, _employee_type], desc: employee.status, desc: employee.id)

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_value), do: :error

  defp page_size(value) when is_integer(value) and value in 1..@max_page_size, do: {:ok, value}
  defp page_size(_value), do: :error

  defp search(value) when is_binary(value), do: {:ok, value}
  defp search(_value), do: :error

  defp type_filter(value) when value in [:all, :human, :agent], do: {:ok, value}
  defp type_filter(_value), do: :error

  defp sort_by(value) when value in [:full_name, :employee_type_label, :status], do: {:ok, value}
  defp sort_by(_value), do: :error

  defp sort_dir(value) when value in [:asc, :desc], do: {:ok, value}
  defp sort_dir(_value), do: :error

  defp unique_keys?(options), do: options |> Keyword.keys() |> Enum.uniq() |> length() == length(options)
  defp page_count(0, _page_size), do: 0
  defp page_count(total_entries, page_size), do: div(total_entries + page_size - 1, page_size)

  defp escape_like(search) do
    search
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
