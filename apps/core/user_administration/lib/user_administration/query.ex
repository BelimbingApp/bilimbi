defmodule Bilimbi.Core.UserAdministration.Query do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.UserAdministration.Entry
  alias Bilimbi.Core.UserAdministration.Options
  alias Bilimbi.Core.UserAdministration.Page
  alias Bilimbi.Core.UserAdministration.Role

  @spec list(Scope.t(), Options.t()) :: Page.t()
  def list(%Scope{} = scope, %Options{} = options) do
    platform_operator? = Scope.platform_operator?(scope)

    query = final_query(options, platform_operator?, scope)
    rows = Repo.all(query)

    to_page(rows, options)
  end

  defp final_query(options, platform_operator?, scope) do
    tenant_companies = tenant_companies(scope)
    live_companies = live_companies()
    visible_role_assignments = visible_role_assignments(platform_operator?)
    filtered_users = filtered_users(options)
    user_total = user_total()
    page_users = page_users(options)
    page_role_rows = page_role_rows()
    page_roles = page_roles()

    from(total in "user_total",
      left_join: user in "page_users",
      on: true,
      left_join: roles in "page_roles",
      on: roles.user_id == user.id,
      select: %{
        total_entries: total.total_entries,
        id: user.id,
        company_id: user.company_id,
        name: user.name,
        email: user.email,
        created_at: user.created_at,
        company_name: user.company_name,
        company_archived: user.company_archived,
        role_ids: roles.role_ids,
        role_names: roles.role_names,
        role_codes: roles.role_codes,
        role_system_flags: roles.role_system_flags
      }
    )
    |> order_final(options)
    |> with_cte("tenant_companies", as: ^tenant_companies)
    |> with_cte("live_companies", as: ^live_companies)
    |> with_cte("visible_role_assignments", as: ^visible_role_assignments)
    |> with_cte("filtered_users", as: ^filtered_users)
    |> with_cte("user_total", as: ^user_total)
    |> with_cte("page_users", as: ^page_users)
    |> with_cte("page_role_rows", as: ^page_role_rows)
    |> with_cte("page_roles", as: ^page_roles)
  end

  # This is the only physical Companies source. Tenancy owns the initial
  # tenant predicate; archived rows deliberately remain in the relation.
  defp tenant_companies(%Scope{} = scope) do
    from(company in Tenancy.scope_query("companies", scope),
      select: %{
        id: company.id,
        tenant_id: company.tenant_id,
        name: company.name,
        deleted_at: company.deleted_at
      }
    )
  end

  defp live_companies do
    from(company in "tenant_companies",
      where: is_nil(company.deleted_at),
      select: %{id: company.id}
    )
  end

  # These are the only physical Authz sources. Joining both live-Company CTEs
  # applies the stricter integration-only corrupt-data policy from ADR 0007.
  defp visible_role_assignments(platform_operator?) do
    from(assignment in "base_authz_principal_roles",
      join: role in "base_authz_roles",
      on: role.id == assignment.role_id,
      left_join: assignment_company in "live_companies",
      on: assignment_company.id == assignment.company_id,
      left_join: role_company in "live_companies",
      on: role_company.id == role.company_id,
      where: assignment.principal_type == "user",
      where: ^assignment_visible(platform_operator?),
      where:
        (role.is_system == true and is_nil(role.company_id)) or
          (role.is_system == false and not is_nil(role_company.id)),
      select: %{
        company_id: assignment.company_id,
        principal_type: assignment.principal_type,
        principal_id: assignment.principal_id,
        role_id: assignment.role_id,
        role_company_id: role.company_id,
        role_name: role.name,
        role_code: role.code,
        role_is_system: role.is_system
      }
    )
  end

  defp assignment_visible(true) do
    dynamic(
      [assignment, _role, assignment_company, _role_company],
      is_nil(assignment.company_id) or not is_nil(assignment_company.id)
    )
  end

  defp assignment_visible(false) do
    dynamic(
      [_assignment, _role, assignment_company, _role_company],
      not is_nil(assignment_company.id)
    )
  end

  # This is the only physical Users source. The inner Company join excludes
  # nil and cross-tenant affiliations before filters, count, and pagination.
  defp filtered_users(%Options{} = options) do
    from(user in "users",
      as: :user,
      join: company in "tenant_companies",
      on: company.id == user.company_id,
      select: %{
        id: user.id,
        company_id: user.company_id,
        name: user.name,
        email: user.email,
        created_at: user.created_at,
        company_name: company.name,
        company_archived: not is_nil(company.deleted_at)
      }
    )
    |> search(options.search)
    |> role_filter(options.role_ids)
  end

  defp search(query, nil), do: query

  defp search(query, search) do
    pattern = "%" <> search <> "%"
    where(query, [user, _company], like(user.name, ^pattern) or like(user.email, ^pattern))
  end

  defp role_filter(query, []), do: query

  defp role_filter(query, role_ids) do
    query
    |> join(:inner, [user, _company], assignment in "visible_role_assignments",
      on: assignment.principal_id == user.id and assignment.role_id in ^role_ids
    )
    |> distinct(true)
  end

  defp user_total do
    from(user in "filtered_users", select: %{total_entries: count(user.id)})
  end

  defp page_users(%Options{} = options) do
    offset = (options.page - 1) * options.page_size

    from(user in "filtered_users",
      select: %{
        id: user.id,
        company_id: user.company_id,
        name: user.name,
        email: user.email,
        created_at: user.created_at,
        company_name: user.company_name,
        company_archived: user.company_archived
      },
      limit: ^options.page_size,
      offset: ^offset
    )
    |> order_page(options)
  end

  defp page_role_rows do
    from(user in "page_users",
      join: role in "visible_role_assignments",
      on: role.principal_id == user.id,
      distinct: true,
      select: %{
        user_id: user.id,
        role_id: role.role_id,
        role_name: role.role_name,
        role_code: role.role_code,
        role_is_system: role.role_is_system
      }
    )
  end

  defp page_roles do
    from(role in "page_role_rows",
      group_by: role.user_id,
      select: %{
        user_id: role.user_id,
        role_ids:
          fragment(
            "array_agg(? ORDER BY ?, ?, ?)",
            role.role_id,
            role.role_name,
            role.role_code,
            role.role_id
          ),
        role_names:
          fragment(
            "array_agg(? ORDER BY ?, ?, ?)",
            role.role_name,
            role.role_name,
            role.role_code,
            role.role_id
          ),
        role_codes:
          fragment(
            "array_agg(? ORDER BY ?, ?, ?)",
            role.role_code,
            role.role_name,
            role.role_code,
            role.role_id
          ),
        role_system_flags:
          fragment(
            "array_agg(? ORDER BY ?, ?, ?)",
            role.role_is_system,
            role.role_name,
            role.role_code,
            role.role_id
          )
      }
    )
  end

  defp order_page(query, %Options{sort_by: :name, sort_dir: :asc}) do
    order_by(query, [row], asc: row.name, desc: row.id)
  end

  defp order_page(query, %Options{sort_by: :name, sort_dir: :desc}) do
    order_by(query, [row], desc: row.name, desc: row.id)
  end

  defp order_page(query, %Options{sort_by: :email, sort_dir: :asc}) do
    order_by(query, [row], asc: row.email, desc: row.id)
  end

  defp order_page(query, %Options{sort_by: :email, sort_dir: :desc}) do
    order_by(query, [row], desc: row.email, desc: row.id)
  end

  defp order_page(query, %Options{sort_by: :company_name, sort_dir: :asc}) do
    order_by(query, [row], asc: row.company_name, desc: row.id)
  end

  defp order_page(query, %Options{sort_by: :company_name, sort_dir: :desc}) do
    order_by(query, [row], desc: row.company_name, desc: row.id)
  end

  defp order_page(query, %Options{sort_by: :created_at, sort_dir: :asc}) do
    order_by(query, [row], asc: row.created_at, desc: row.id)
  end

  defp order_page(query, %Options{sort_by: :created_at, sort_dir: :desc}) do
    order_by(query, [row], desc: row.created_at, desc: row.id)
  end

  defp order_final(query, %Options{sort_by: :name, sort_dir: :asc}) do
    order_by(query, [_total, row], asc: row.name, desc: row.id)
  end

  defp order_final(query, %Options{sort_by: :name, sort_dir: :desc}) do
    order_by(query, [_total, row], desc: row.name, desc: row.id)
  end

  defp order_final(query, %Options{sort_by: :email, sort_dir: :asc}) do
    order_by(query, [_total, row], asc: row.email, desc: row.id)
  end

  defp order_final(query, %Options{sort_by: :email, sort_dir: :desc}) do
    order_by(query, [_total, row], desc: row.email, desc: row.id)
  end

  defp order_final(query, %Options{sort_by: :company_name, sort_dir: :asc}) do
    order_by(query, [_total, row], asc: row.company_name, desc: row.id)
  end

  defp order_final(query, %Options{sort_by: :company_name, sort_dir: :desc}) do
    order_by(query, [_total, row], desc: row.company_name, desc: row.id)
  end

  defp order_final(query, %Options{sort_by: :created_at, sort_dir: :asc}) do
    order_by(query, [_total, row], asc: row.created_at, desc: row.id)
  end

  defp order_final(query, %Options{sort_by: :created_at, sort_dir: :desc}) do
    order_by(query, [_total, row], desc: row.created_at, desc: row.id)
  end

  defp to_page([%{total_entries: total_entries} | _] = rows, %Options{} = options) do
    entries =
      rows
      |> Enum.reject(&is_nil(&1.id))
      |> Enum.map(&to_entry/1)

    %Page{
      entries: entries,
      page: options.page,
      page_size: options.page_size,
      total_entries: total_entries,
      total_pages: total_pages(total_entries, options.page_size)
    }
  end

  defp to_entry(row) do
    %Entry{
      id: row.id,
      company_id: row.company_id,
      name: row.name,
      email: row.email,
      created_at: row.created_at,
      company_name: row.company_name,
      company_archived: row.company_archived,
      roles: roles(row)
    }
  end

  defp roles(%{role_ids: nil}), do: []

  defp roles(row) do
    [row.role_ids, row.role_names, row.role_codes, row.role_system_flags]
    |> Enum.zip()
    |> Enum.map(fn {id, name, code, is_system} ->
      %Role{id: id, name: name, code: code, is_system: is_system}
    end)
  end

  defp total_pages(0, _page_size), do: 0
  defp total_pages(total_entries, page_size), do: div(total_entries + page_size - 1, page_size)
end
