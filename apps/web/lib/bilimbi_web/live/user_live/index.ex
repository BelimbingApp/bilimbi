defmodule BilimbiWeb.UserLive.Index do
  @moduledoc """
  Tenant-wide user list, via `Bilimbi.Core.User.list_users/1`.

  Visibility matches Belimbing: affiliation is through any company owned by
  the tenant (including soft-deleted ones); a user with no company appears
  in no tenant list.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    {:ok, users} = User.list_users(scope)
    {:ok, companies} = Company.list_companies(scope)

    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> assign(:active_nav, :users)
     |> assign(:company_names, Map.new(companies, &{&1.id, Company.Summary.display_name(&1)}))
     |> stream(:users, users)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-4xl">
        <.header>
          Users
          <:subtitle>Every user affiliated with a company in this tenant</:subtitle>
        </.header>

        <div class="mt-5">
          <.table id="users" rows={@streams.users}>
            <:col :let={{_id, user}} label="Name">
              <span class="font-medium">{user.name}</span>
            </:col>
            <:col :let={{_id, user}} label="Email">{user.email}</:col>
            <:col :let={{_id, user}} label="Company">
              <%= if name = @company_names[user.company_id] do %>
                <.link
                  :if={user.company_id}
                  navigate={~p"/companies/#{user.company_id}"}
                  class="text-ink-muted hover:text-ink hover:underline"
                >
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
      </div>
    </Layouts.app>
    """
  end
end
