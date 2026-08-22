defmodule Bilimbi.Core.User.Web.CompanyUsersPanel do
  @moduledoc """
  Company-page users panel, contributed as a discovered embed.

  Core User owns the company-users read; the company page renders it by the
  `"company.users"` manifest key and never names this module (#595). Ported
  behaviour-for-behaviour from the company show page's former inline Users
  section, which reached `User.list_company_users/2` through a
  `Code.ensure_loaded?` + `function_exported?` probe.

  The panel is read-only and carries no capability of its own: the company
  route already gates on `admin.company.view`, and this list is the same
  informational content the section rendered unconditionally before. There is
  no write here, so `<.discovered_panel>` renders it for anyone who reaches the
  company page. The filter/sort/page events still parse-don't-crash on forged
  params (#661), because a read surface must survive garbage input too.

  Mirrors the `company.employees` embed shape (#595) so the two company-page
  discovered panels stay uniform.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Core.User

  @page_sizes [25, 50, 100, 300]
  @default_state %{search: nil, sort_by: "name", sort_dir: :asc, page: 1, per_page: 25}
  @sortable ~w(name email email_verified)

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> reload()}
  end

  # Deliberately strict, matching the employees/address panels (#409): the
  # company page resolved this company before rendering the panel, so a non-ok
  # here is infrastructure failure or a mid-session deletion — raising reaches
  # the recovery boundary instead of rendering a broken section as an empty one.
  defp reload(socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company_id
    table_state = normalize_table_state(socket.assigns[:table_state])
    page_sizes = socket.assigns[:page_sizes] || @page_sizes
    {:ok, users} = User.list_company_users(scope, company_id)
    users_page = build_page(users, table_state)

    socket
    |> assign(:users, users)
    |> assign(:users_count, length(users))
    |> assign(:users_page, users_page)
    |> assign(:page_sizes, page_sizes)
    |> assign(:table_state, table_state)
    |> assign(:filters_form, to_form(filters_form_params(table_state), as: :users_filters))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.card id={@id} class="mt-6">
      <div class="flex items-center gap-2 mb-4">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
          Users
        </h3>
        <.badge>{@users_count}</.badge>
      </div>
      <.form
        for={@filters_form}
        id="company-users-filters"
        phx-change="users_filters"
        class="p-2 mb-2 rounded-xl border border-line bg-surface-muted"
      >
        <div class="relative">
          <.icon
            name="hero-magnifying-glass"
            class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
          />
          <.input
            field={@filters_form[:search]}
            id="company-users-search"
            type="search"
            phx-debounce="300"
            maxlength="255"
            label="Search users"
            label_class="sr-only"
            wrapper_class="mb-0"
            placeholder="Search by name or email..."
            class="rounded-lg pl-8"
          />
        </div>
      </.form>
      <.table
        id="company-users-table"
        rows={@users_page.entries}
        row_id={fn user -> "company-user-#{user.id}" end}
        row_item={fn user -> user end}
        sort_by={@table_state.sort_by}
        sort_dir={@table_state.sort_dir}
        sort_event="users_sort"
        caption="Users"
      >
        <:col :let={user} label="Name" sort="name" sort_id="company-users-sort-name">
          <span class="font-medium">{user.name}</span>
        </:col>
        <:col :let={user} label="Email" sort="email" sort_id="company-users-sort-email">
          {user.email}
        </:col>
        <:col
          :let={user}
          label="Email verified"
          sort="email_verified"
          sort_id="company-users-sort-email-verified"
        >
          <.badge kind={if user.email_verified_at, do: :success, else: :warning}>
            {if user.email_verified_at, do: "verified", else: "unverified"}
          </.badge>
        </:col>
        <:empty :if={@users_page.total_entries == 0}>
          No users found for this company.
        </:empty>
      </.table>
      <.pagination
        id="company-users-pagination"
        page={@users_page}
        page_sizes={@page_sizes}
        filters_form={@filters_form}
        filters_event="users_filters"
        page_event="users_page"
      />
    </.card>
    """
  end

  defp normalize_table_state(%{} = state) do
    %{
      search: normalize_search(state[:search]),
      sort_by: normalize_sort_by(state[:sort_by]),
      sort_dir: normalize_sort_dir(state[:sort_dir]),
      page: normalize_page(state[:page]),
      per_page: normalize_page_size(state[:per_page])
    }
  end

  defp normalize_table_state(_state), do: @default_state

  defp build_page(users, state) do
    filtered =
      users
      |> Enum.filter(&matches_search?(&1, state.search && String.downcase(state.search)))
      |> Enum.sort_by(&sort_value(&1, state.sort_by))

    sorted = if state.sort_dir == :desc, do: Enum.reverse(filtered), else: filtered
    total_entries = length(sorted)
    total_pages = total_pages(total_entries, state.per_page)
    page = clamp_page(state.page, total_pages)
    entries = Enum.slice(sorted, (page - 1) * state.per_page, state.per_page)

    %{
      entries: entries,
      page: page,
      page_size: state.per_page,
      total_entries: total_entries,
      total_pages: total_pages,
      has_prev?: total_pages > 0 and page > 1,
      has_next?: total_pages > 0 and page < total_pages
    }
  end

  defp total_pages(0, _page_size), do: 0
  defp total_pages(total_entries, page_size), do: ceil(total_entries / page_size)

  defp clamp_page(_page, 0), do: 1
  defp clamp_page(page, total_pages), do: min(max(page, 1), total_pages)

  defp matches_search?(_user, nil), do: true

  defp matches_search?(user, search) do
    [user.name, user.email]
    |> Enum.any?(fn value ->
      value |> to_string() |> String.downcase() |> String.contains?(search)
    end)
  end

  defp sort_value(user, "name"), do: sort_string(user.name)
  defp sort_value(user, "email"), do: sort_string(user.email)
  defp sort_value(user, "email_verified"), do: if(user.email_verified_at, do: 0, else: 1)
  defp sort_value(user, _sort), do: sort_value(user, "name")

  defp filters_form_params(state) do
    %{
      "search" => state.search || "",
      "perPage" => to_string(state.per_page)
    }
  end

  defp normalize_search(nil), do: nil

  defp normalize_search(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_search(_value), do: nil

  defp normalize_sort_by(value) when value in @sortable, do: value
  defp normalize_sort_by(_value), do: @default_state.sort_by

  defp normalize_sort_dir(value) when value in [:asc, :desc], do: value

  defp normalize_sort_dir(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "desc" -> :desc
      "asc" -> :asc
      _ -> @default_state.sort_dir
    end
  end

  defp normalize_sort_dir(_value), do: @default_state.sort_dir

  defp normalize_page(value) do
    case positive_integer(value) do
      page when is_integer(page) -> page
      _ -> @default_state.page
    end
  end

  defp normalize_page_size(value) do
    case positive_integer(value) do
      size when size in @page_sizes -> size
      _ -> @default_state.per_page
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp sort_string(nil), do: ""
  defp sort_string(value), do: value |> to_string() |> String.downcase()
end
