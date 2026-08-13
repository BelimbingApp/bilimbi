defmodule Bilimbi.Core.User.Web.IndexLive do
  @moduledoc """
  Tenant-wide user management list.

  Tenant visibility deliberately includes accounts whose company is archived,
  matching Belimbing's left join. Accounts without a company have no tenant
  affiliation and therefore do not appear.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    {:ok, users} = User.list_users(scope)
    {:ok, companies} = Company.list_companies(scope)

    {:ok,
     socket
     |> assign(:page_title, "User Management")
     |> assign(:active_nav, :users)
     |> assign(:company_names, Map.new(companies, &{&1.id, Company.Summary.display_name(&1)}))
     |> stream(:users, users)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-5xl">
        <.header>
          User Management
          <:actions>
            <.button :if={allowed?(@current_scope, "admin.user.create")} id="user-new" navigate={~p"/users/new"} variant="primary">
              <.icon name="hero-plus" /> Create User
            </.button>
          </:actions>
        </.header>

        <.table id="users" rows={@streams.users}>
          <:col :let={{_id, user}} label="Name">
            <div class="flex items-center gap-3">
              <span class="grid size-8 place-items-center rounded-full bg-surface-sunken text-xs font-semibold text-ink">
                {initials(user.name)}
              </span>
              <.link navigate={~p"/users/#{user.id}"} class="font-medium text-ink-strong hover:underline">
                {user.name}
              </.link>
            </div>
          </:col>
          <:col :let={{_id, user}} label="Email">{user.email}</:col>
          <:col :let={{_id, user}} label="Company">
            <%= if name = @company_names[user.company_id] do %>
              <.link navigate={~p"/companies/#{user.company_id}"} class="text-ink-muted hover:text-ink hover:underline">
                {name}
              </.link>
            <% else %>
              <span class="text-ink-faint">—</span>
            <% end %>
          </:col>
          <:col :let={{_id, user}} label="Email verified">
            <.badge kind={if user.email_verified_at, do: :success, else: :warning}>
              {if user.email_verified_at, do: "verified", else: "unverified"}
            </.badge>
          </:col>
        </.table>
      </div>
    </Layouts.app>
    """
  end

  defp allowed?(%{capabilities: capabilities}, capability), do: capability in capabilities
  defp allowed?(_scope, _capability), do: false

  defp initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp initials(_name), do: "?"
end
