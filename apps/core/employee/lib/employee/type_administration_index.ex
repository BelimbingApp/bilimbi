defmodule Bilimbi.Core.Employee.TypeAdministrationIndex do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Employee.EmployeeType
  alias Bilimbi.Core.Employee.Schema
  alias Bilimbi.Core.Employee.TypeAdministrationEntry
  alias Bilimbi.Core.Employee.TypeAdministrationPage

  @default_page 1
  @default_page_size 25
  @max_page_size 300
  @allowed_option_keys [:page, :page_size, :search, :sort_by, :sort_dir]

  @type normalized_options :: %{
          page: pos_integer(),
          page_size: pos_integer(),
          search: String.t(),
          sort_by: :code | :label | :is_system | :employees_count,
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
         {:ok, sort_by} <- sort_by(Keyword.get(options, :sort_by, :is_system)),
         {:ok, sort_dir} <- sort_dir(Keyword.get(options, :sort_dir, :desc)) do
      {:ok,
       %{
         page: page,
         page_size: page_size,
         search: search,
         sort_by: sort_by,
         sort_dir: sort_dir
       }}
    else
      _ -> {:error, :invalid_options}
    end
  end

  def normalize_options(_options), do: {:error, :invalid_options}

  @spec page(pos_integer(), normalized_options()) :: TypeAdministrationPage.t()
  def page(company_id, options) do
    base =
      company_id
      |> base_query()
      |> apply_search(options.search)

    total_entries =
      base
      |> select([type, _emp], count(type.id, :distinct))
      |> Repo.one() || 0

    total_pages = page_count(total_entries, options.page_size)

    entries =
      base
      |> group_by([type, _emp], [type.id, type.code, type.label, type.is_system, type.company_id])
      |> select([type, emp], {type, count(emp.id)})
      |> apply_order(options.sort_by, options.sort_dir)
      |> offset(^((options.page - 1) * options.page_size))
      |> limit(^options.page_size)
      |> Repo.all()
      |> Enum.map(&TypeAdministrationEntry.from_query_result/1)

    %TypeAdministrationPage{
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
    from type in EmployeeType,
      left_join: emp in Schema,
      on: emp.company_id == ^company_id and emp.employee_type == type.code,
      where:
        (type.is_system == true and is_nil(type.company_id)) or
          type.company_id == ^company_id
  end

  defp apply_search(query, ""), do: query

  defp apply_search(query, search) do
    pattern = "%#{escape_like(search)}%"

    where(
      query,
      [type, _emp],
      fragment("? ILIKE ? ESCAPE E'\\\\'", type.code, ^pattern) or
        fragment("? ILIKE ? ESCAPE E'\\\\'", type.label, ^pattern)
    )
  end

  defp apply_order(query, :code, :asc),
    do: order_by(query, [type, _emp], asc: type.code, desc: type.id)

  defp apply_order(query, :code, :desc),
    do: order_by(query, [type, _emp], desc: type.code, desc: type.id)

  defp apply_order(query, :label, :asc),
    do: order_by(query, [type, _emp], asc: type.label, asc: type.code, desc: type.id)

  defp apply_order(query, :label, :desc),
    do: order_by(query, [type, _emp], desc: type.label, asc: type.code, desc: type.id)

  defp apply_order(query, :is_system, :asc),
    do:
      order_by(query, [type, _emp],
        asc: type.is_system,
        asc: type.label,
        asc: type.code,
        desc: type.id
      )

  defp apply_order(query, :is_system, :desc),
    do:
      order_by(query, [type, _emp],
        desc: type.is_system,
        asc: type.label,
        asc: type.code,
        desc: type.id
      )

  defp apply_order(query, :employees_count, :asc),
    do:
      order_by(query, [type, emp],
        asc: count(emp.id),
        desc: type.is_system,
        asc: type.label,
        desc: type.id
      )

  defp apply_order(query, :employees_count, :desc),
    do:
      order_by(query, [type, emp],
        desc: count(emp.id),
        desc: type.is_system,
        asc: type.label,
        desc: type.id
      )

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_value), do: :error

  defp page_size(value) when is_integer(value) and value in 1..@max_page_size, do: {:ok, value}
  defp page_size(_value), do: :error

  defp search(nil), do: {:ok, ""}
  defp search(value) when is_binary(value), do: {:ok, value}
  defp search(_value), do: :error

  defp sort_by(value) when value in [:code, :label, :is_system, :employees_count],
    do: {:ok, value}

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
