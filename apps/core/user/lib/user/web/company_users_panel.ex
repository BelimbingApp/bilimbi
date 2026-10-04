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

  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Core.User

  @page_sizes [25, 50, 100, 300]

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
    table_state = socket.assigns.table_state
    page_sizes = socket.assigns[:page_sizes] || @page_sizes
    {:ok, users} = User.list_company_users(scope, company_id)
    users_page = users |> filter_and_sort(table_state) |> ListState.paginate(table_state)

    socket
    |> assign(:users, users)
    |> assign(:users_count, length(users))
    |> assign(:users_page, users_page)
    |> assign(:page_sizes, page_sizes)
    |> assign(:filters_form, ListState.filters_form(table_state, as: :users_filters))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="contents">
      <.card class="mt-6">
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
        class="mb-2"
      >
        <div class="relative">
          <.icon
            name="search"
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
            class="block w-full rounded-md border border-high-contrast-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-brand-strong focus:outline-none focus:ring-2 focus:ring-brand-strong/30 disabled:cursor-not-allowed disabled:bg-surface-sunken disabled:text-ink-subtle"
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
    </div>
    """
  end

  # The company page parses the URL once and passes the `ListState`; this
  # panel only filters and sorts the rows it listed, and `ListState.paginate/2`
  # slices them.
  defp filter_and_sort(users, state) do
    search = state.search |> String.trim() |> String.downcase()

    sorted =
      users
      |> Enum.filter(&matches_search?(&1, search))
      |> Enum.sort_by(&sort_value(&1, state.sort_by))

    if state.sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp matches_search?(_user, ""), do: true

  defp matches_search?(user, search) do
    [user.name, user.email]
    |> Enum.any?(fn value ->
      value |> to_string() |> String.downcase() |> String.contains?(search)
    end)
  end

  defp sort_value(user, :name), do: sort_string(user.name)
  defp sort_value(user, :email), do: sort_string(user.email)
  defp sort_value(user, :email_verified), do: if(user.email_verified_at, do: 0, else: 1)

  defp sort_string(nil), do: ""
  defp sort_string(value), do: value |> to_string() |> String.downcase()
end
