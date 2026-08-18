defmodule BilimbiWeb.ImpersonationController do
  @moduledoc """
  Endpoints allowing administrators with `admin.user.impersonate` capability
  to impersonate another user in their tenant workspace.
  """

  use BilimbiWeb, :controller

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Summary
  alias BilimbiWeb.UserAuth

  def create(conn, %{"id" => id}) do
    current_scope = conn.assigns[:current_scope]

    with %{actor: actor, scope: scope, user: %{"user_id" => current_user_id} = current_user} <-
           current_scope,
         %Decision{allowed: true} <- Authz.can(actor, "admin.user.impersonate") do
      if current_scope.impersonator != nil do
        conn
        |> put_flash(:error, gettext("Cannot impersonate while impersonating."))
        |> redirect(to: ~p"/dashboard")
      else
        case Integer.parse(to_string(id)) do
          {target_user_id, ""} when target_user_id != current_user_id ->
            case User.get_tenant_user(scope, target_user_id) do
              {:ok, %Summary{} = target_user} ->
                UserAuth.impersonate_user(conn, current_user, target_user)

              {:error, _reason} ->
                conn
                |> put_flash(:error, gettext("Unable to find that user in this workspace."))
                |> redirect(to: ~p"/users")
            end

          _ ->
            conn
            |> put_flash(:error, gettext("You cannot impersonate yourself."))
            |> redirect(to: ~p"/users")
        end
      end
    else
      _ ->
        conn
        |> put_flash(:error, gettext("You do not have access to that action."))
        |> redirect(to: ~p"/dashboard")
    end
  end

  def delete(conn, _params) do
    UserAuth.leave_impersonation(conn)
  end
end
