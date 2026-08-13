defmodule BilimbiWeb.UserLive.Show do
  @moduledoc """
  One user in this tenant, via `Bilimbi.Core.User` scoped reads.

  The tenant-wide `list_users/1` locates the user's company affiliation;
  `get_user/3` then proves the record inside that company boundary. Both
  reads are live, so a user moved or removed between renders is reported
  as missing rather than served stale.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias BilimbiWeb.UserAuth

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope.scope

    with {user_id, ""} <- Integer.parse(id),
         {:ok, users} <- User.list_users(scope),
         %User.Summary{company_id: company_id} when is_integer(company_id) <-
           Enum.find(users, &(&1.id == user_id)),
         {:ok, user} <- User.get_user(scope, company_id, user_id) do
      {:ok, companies} = Company.list_companies(scope)

      {:ok,
       socket
       |> assign(:page_title, user.name)
       |> assign(:active_nav, :users)
       |> assign(:user, user)
       |> assign(:company_name, company_name(companies, user.company_id))}
    else
      _ -> {:ok, not_found(socket)}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    scope = socket.assigns.current_scope.scope
    user = socket.assigns.user

    cond do
      user.id == socket.assigns.current_scope.user["user_id"] ->
        {:noreply, put_flash(socket, :error, "You cannot delete your own account here.")}

      not UserAuth.allowed?(socket.assigns.current_scope, "admin.user.delete") ->
        {:noreply, put_flash(socket, :error, "You do not have access to that action.")}

      true ->
        case User.delete_user(scope, user.company_id, user.id) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "#{user.name} was deleted.")
             |> push_navigate(to: ~p"/users")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "That user could not be deleted.")}
        end
    end
  end

  defp company_name(companies, company_id) do
    case Enum.find(companies, &(&1.id == company_id)) do
      nil -> nil
      company -> Company.Summary.display_name(company)
    end
  end

  defp not_found(socket) do
    socket
    |> put_flash(:error, "That user does not exist in this workspace.")
    |> push_navigate(to: ~p"/users")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-4xl">
        <p class="mb-2 text-xs">
          <.link navigate={~p"/users"} class="font-medium text-ink-muted hover:text-ink">
            ← Users
          </.link>
        </p>

        <.header>
          {@user.name}
          <:subtitle>
            <span class="text-ink-subtle">{@user.email}</span>
          </:subtitle>
          <:actions>
            <.badge kind={if @user.email_verified_at, do: :success, else: :warning}>
              {if @user.email_verified_at, do: "verified", else: "unverified"}
            </.badge>
            <.link
              :if={UserAuth.allowed?(@current_scope, "admin.user.update")}
              navigate={~p"/users/#{@user.id}/edit"}
              id="user-edit"
              class="rounded-md px-2.5 py-1.5 text-xs font-medium text-ink-muted ring-1 ring-line transition hover:bg-surface-sunken hover:text-ink"
            >
              Edit
            </.link>
          </:actions>
        </.header>

        <div class="mt-5">
          <.list>
            <:item title="Company">
              <%= if @company_name do %>
                <.link
                  navigate={~p"/companies/#{@user.company_id}"}
                  class="text-ink-muted hover:text-ink hover:underline"
                >
                  {@company_name}
                </.link>
              <% else %>
                <span class="text-ink-faint">—</span>
              <% end %>
            </:item>
            <:item title="Employee ID">
              <%= if @user.employee_id do %>
                <span class="tabular-nums">{@user.employee_id}</span>
              <% else %>
                <span class="text-ink-faint">—</span>
              <% end %>
            </:item>
            <:item title="Email verified at">
              <%= if @user.email_verified_at do %>
                {@user.email_verified_at}
              <% else %>
                <span class="text-ink-faint">not yet</span>
              <% end %>
            </:item>
          </.list>
        </div>

        <div
          :if={UserAuth.allowed?(@current_scope, "admin.user.delete")}
          id="user-danger"
          class="mt-8 rounded-xl border border-line bg-surface px-5 py-4"
        >
          <div class="flex items-center justify-between gap-4">
            <div>
              <h2 class="text-sm font-semibold text-ink-strong">Delete this user</h2>
              <p class="mt-0.5 text-xs text-ink-subtle">
                Removes the account. Sessions and audit history are governed by their own modules.
              </p>
            </div>
            <.button
              id="user-delete"
              phx-click="delete"
              data-confirm={"Delete #{@user.name}? This cannot be undone."}
              class="bg-danger text-sm font-medium text-ink-inverse transition hover:opacity-90"
            >
              Delete user
            </.button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
