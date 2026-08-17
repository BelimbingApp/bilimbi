defmodule Bilimbi.Core.User.Web.ShowLive do
  @moduledoc """
  Shows one tenant-visible user and provides the irreversible delete action.

  Read visibility includes users affiliated to archived companies. Writes use
  Core User's company-scoped API, so an archived affiliation is explained
  honestly rather than treated as a missing user.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope.scope

    with {user_id, ""} <- Integer.parse(id),
         {:ok, user} <- User.get_tenant_user(scope, user_id) do
      {:ok, companies} = Company.list_companies(scope)

      {:ok,
       socket
       |> assign(:page_title, user.name)
       |> assign(:active_nav, "admin.user")
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
        {:noreply, put_flash(socket, :error, "You cannot delete your own account.")}

      not allowed?(socket.assigns.current_scope, "admin.user.delete") ->
        {:noreply, put_flash(socket, :error, "You do not have permission to delete users.")}

      true ->
        case User.delete_user(scope, user.company_id, user.id) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "User deleted successfully.")
             |> push_navigate(to: ~p"/users")}

          {:error, :company_not_found} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "That user cannot be deleted while their company is archived."
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "That user could not be deleted.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-4xl">
        <.header>
          {@user.name}
          <:subtitle>User details</:subtitle>
          <:actions>
            <.button id="user-back" navigate={~p"/users"}>
              Back
            </.button>
            <.button
              :if={allowed?(@current_scope, "admin.user.update")}
              id="user-edit"
              navigate={~p"/users/#{@user.id}/edit"}
              variant="primary"
            >
              Edit user
            </.button>
          </:actions>
        </.header>

        <section class="rounded-xl border border-line bg-surface px-5 py-4" aria-labelledby="user-details-title">
          <h2 id="user-details-title" class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">User Details</h2>
          <.list>
            <:item title="Name">{@user.name}</:item>
            <:item title="Email">{@user.email}</:item>
            <:item title="Company">
              <%= if @company_name do %>
                <.link navigate={~p"/companies/#{@user.company_id}"} class="text-ink-muted hover:text-ink hover:underline">
                  {@company_name}
                </.link>
              <% else %>
                <span class="text-ink-faint">None</span>
              <% end %>
            </:item>
            <:item title="Email Verified">
              <.badge kind={if @user.email_verified_at, do: :success, else: :warning}>
                {if @user.email_verified_at, do: "verified", else: "unverified"}
              </.badge>
            </:item>
          </.list>
        </section>

        <section :if={allowed?(@current_scope, "admin.user.delete")} id="user-danger" class="mt-8 rounded-xl border border-danger-line bg-danger-surface px-5 py-4">
          <div class="flex items-center justify-between gap-4">
            <div>
              <h2 class="text-sm font-semibold text-danger-ink">Delete this user</h2>
              <p class="mt-0.5 text-xs text-danger-ink">Permanently deletes this account. This cannot be undone.</p>
            </div>
            <.button id="user-delete" phx-click="delete" data-confirm={"Delete #{@user.name}? This cannot be undone."} class="border-danger bg-danger text-sm font-medium text-action-ink hover:opacity-90">
              Delete user
            </.button>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
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
end
