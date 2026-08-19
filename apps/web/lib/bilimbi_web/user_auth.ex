defmodule BilimbiWeb.UserAuth do
  @moduledoc """
  Web-edge authentication: session handling, scope propagation, and the
  LiveView `on_mount` hooks for the authenticated shell.

  Business rules stay in the deep modules — `Bilimbi.Core.User` verifies
  credentials, `Bilimbi.Base.Tenancy` proves the tenant, `Bilimbi.Base.Session`
  owns the durable session row, and `Bilimbi.Base.Authz` decides capabilities.
  This module only carries proof across the Phoenix boundary.

  ## Session shape

  The Phoenix cookie stores only stable IDs under `"current_user"`:
  `session_id`, `user_id`, and `company_id`. Display fields and tenant
  identity are never taken from the cookie. Every HTTP and LiveView
  boundary rehydrates from live data:

    1. `Session.fetch_session/1` — a terminated row ends the cookie;
    2. the durable row's `user_id` must match the cookie;
    3. `Company.fetch_tenant_id_for_company/1` then `Tenancy.scope/1`;
    4. `User.get_user/3` must return that user in that company.

  Any miss fails closed and the request is unauthenticated. Login writes
  a cryptographically strong session id through `Session.put_session/3`
  with an opaque payload; logout calls `Session.delete_session/1` before
  dropping the cookie.

  ## Cross-module seam

  `Bilimbi.Core.Company.fetch_tenant_id_for_company/1` is the public
  company → tenant read for the login edge (issue #87, PR #95) — the same
  exception class as `User.authenticate/2`'s unscoped email lookup. It
  fails closed for absent, soft-deleted, or invalid IDs; tenant liveness
  is re-proven by `Tenancy.scope/1` on every request.
  """

  import Plug.Conn
  import Phoenix.Controller

  use BilimbiWeb, :verified_routes

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Session.Entry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Summary

  @session_key "current_user"
  @impersonation_key "impersonation"
  @return_to_key "user_return_to"
  @login_token_salt "session-login"
  @login_token_max_age 120
  # Opaque compatibility payload. Web never interprets session contents.
  @opaque_payload "{}"
  @denied_message "You do not have access to that page."

  # ------------------------------------------------------------------
  # Login edge
  # ------------------------------------------------------------------

  @doc """
  Verifies credentials at the login edge through
  `Bilimbi.Core.User.authenticate/2`. Throttling is the caller's concern
  (see `BilimbiWeb.RateLimit`).
  """
  @spec authenticate(String.t(), String.t()) ::
          {:ok, Summary.t()} | {:error, :invalid_credentials}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    case User.authenticate(email, password) do
      {:ok, %Summary{} = user} -> {:ok, user}
      {:error, _reason} -> {:error, :invalid_credentials}
    end
  end

  @doc """
  Signs a short-lived token carrying the stable IDs for
  `SessionController`. The map is signed so a tampered hidden field cannot
  smuggle another user or company into the session write.
  """
  @spec sign_login_token(map()) :: binary()
  def sign_login_token(%{} = session_user) do
    Phoenix.Token.sign(BilimbiWeb.Endpoint, @login_token_salt, session_user)
  end

  @doc "Verifies a token produced by `sign_login_token/1`."
  @spec verify_login_token(binary()) :: {:ok, map()} | {:error, :invalid | :expired}
  def verify_login_token(token) when is_binary(token) do
    case Phoenix.Token.verify(BilimbiWeb.Endpoint, @login_token_salt, token,
           max_age: @login_token_max_age
         ) do
      {:ok, session_user} when is_map(session_user) -> {:ok, session_user}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Builds the login-token payload for a freshly authenticated user: stable
  IDs only, after the company → tenant seam proves a tenant is available.
  Display fields are loaded later from live User and Company rows.
  """
  @spec session_user(Summary.t()) :: {:ok, map()} | {:error, :tenant_unavailable}
  def session_user(%Summary{} = user) do
    with {:ok, _tenant_id} <- tenant_id_for_user(user) do
      {:ok,
       %{
         "user_id" => user.id,
         "company_id" => user.company_id
       }}
    end
  end

  # Belimbing resolves the tenant from the user's current company
  # (TenantContext). The public company → tenant read fails closed for
  # absent, soft-deleted, or invalid IDs; tenant liveness itself is
  # re-proven by Tenancy.scope/1 on every request.
  defp tenant_id_for_user(%Summary{company_id: nil}), do: {:error, :tenant_unavailable}

  defp tenant_id_for_user(%Summary{company_id: company_id}) do
    case Company.fetch_tenant_id_for_company(company_id) do
      {:ok, tenant_id} -> {:ok, tenant_id}
      {:error, :not_found} -> {:error, :tenant_unavailable}
    end
  end

  # ------------------------------------------------------------------
  # Session lifecycle
  # ------------------------------------------------------------------

  @doc """
  Persists a durable Base Session row, stores only stable IDs in the
  Phoenix cookie, renews the session, and redirects.
  """
  def log_in_user(conn, session_user, return_to \\ nil)

  def log_in_user(conn, %{"user_id" => user_id, "company_id" => company_id}, return_to)
      when is_integer(user_id) and is_integer(company_id) do
    case persist_durable_session(conn, user_id, company_id) do
      {:ok, session_id} ->
        destination = return_to || get_session(conn, @return_to_key) || ~p"/dashboard"

        conn
        |> configure_session(renew: true)
        |> delete_session(@return_to_key)
        |> put_session(@session_key, %{
          "session_id" => session_id,
          "user_id" => user_id,
          "company_id" => company_id
        })
        |> redirect(to: destination)

      :error ->
        reject_login(conn)
    end
  end

  def log_in_user(conn, _session_user, _return_to), do: reject_login(conn)

  defp reject_login(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_flash(:error, "That sign-in expired. Please sign in again.")
    |> redirect(to: ~p"/")
  end

  defp persist_durable_session(conn, user_id, company_id, existing_session_id \\ nil) do
    with {:ok, tenant_id} <- Company.fetch_tenant_id_for_company(company_id),
         {:ok, %Scope{} = scope} <- Tenancy.scope(tenant_id),
         {:ok, %Summary{id: ^user_id}} <- User.get_user(scope, company_id, user_id) do
      session_id = existing_session_id || generate_session_id()

      attributes = %{
        user_id: user_id,
        ip_address: request_ip(conn),
        user_agent: request_user_agent(conn),
        last_activity: System.system_time(:second)
      }

      case Session.put_session(session_id, @opaque_payload, attributes) do
        {:ok, %Entry{}} -> {:ok, session_id}
        {:error, _changeset} -> :error
      end
    else
      _ -> :error
    end
  end

  defp current_session_id(conn) do
    case get_session(conn, @session_key) do
      %{"session_id" => session_id} when is_binary(session_id) and session_id != "" -> session_id
      _ -> nil
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp request_ip(conn) do
    case conn.remote_ip do
      ip when is_tuple(ip) -> ip |> :inet.ntoa() |> to_string()
      _ -> nil
    end
  end

  defp request_user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [user_agent | _] -> user_agent
      _ -> nil
    end
  end

  @doc "Deletes the durable session row, drops the cookie, and redirects to login."
  def log_out_user(conn) do
    case get_session(conn, @session_key) do
      %{"session_id" => session_id} when is_binary(session_id) ->
        Session.delete_session(session_id)

      _ ->
        :ok
    end

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  @doc """
  Switches the active session to `target_user` and records the administrator's
  identity in the `@impersonation_key` cookie payload. Updates the durable session
  row in place without leaving stranded authentication records.
  """
  def impersonate_user(
        conn,
        %{"user_id" => original_user_id, "name" => original_user_name},
        %Summary{} = target_user
      )
      when is_integer(original_user_id) and is_binary(original_user_name) do
    current_id = current_session_id(conn)

    with {:ok, _target_session_user} <- session_user(target_user),
         {:ok, session_id} <-
           persist_durable_session(conn, target_user.id, target_user.company_id, current_id) do
      conn
      |> configure_session(renew: true)
      |> put_session(@impersonation_key, %{
        "original_user_id" => original_user_id,
        "original_user_name" => original_user_name
      })
      |> put_session(@session_key, %{
        "session_id" => session_id,
        "user_id" => target_user.id,
        "company_id" => target_user.company_id
      })
      |> redirect(to: ~p"/dashboard")
    else
      _ ->
        conn
        |> put_flash(:error, "Unable to impersonate that user.")
        |> redirect(to: ~p"/users")
    end
  end

  @doc """
  Leaves impersonation by clearing `@impersonation_key` and restoring the
  original administrator's authenticated session in place.
  """
  def leave_impersonation(conn) do
    case get_session(conn, @impersonation_key) do
      %{"original_user_id" => original_user_id} when is_integer(original_user_id) ->
        scope = conn.assigns[:current_scope] && conn.assigns[:current_scope].scope
        current_id = current_session_id(conn)

        with %Scope{} <- scope,
             {:ok, %Summary{} = original_user} <- User.get_tenant_user(scope, original_user_id),
             {:ok, session_id} <-
               persist_durable_session(
                 conn,
                 original_user.id,
                 original_user.company_id,
                 current_id
               ) do
          conn
          |> configure_session(renew: true)
          |> delete_session(@impersonation_key)
          |> put_session(@session_key, %{
            "session_id" => session_id,
            "user_id" => original_user.id,
            "company_id" => original_user.company_id
          })
          |> redirect(to: ~p"/dashboard")
        else
          _ ->
            log_out_user(conn)
        end

      _ ->
        redirect(conn, to: ~p"/dashboard")
    end
  end

  # ------------------------------------------------------------------
  # Plugs
  # ------------------------------------------------------------------

  @doc """
  Loads `conn.assigns.current_scope` from live identity. The assign is a map
  `%{user: map, scope: Scope.t(), actor: Authz.Actor.t(), capabilities: [String.t()], impersonator: map | nil, operator_company_missing: boolean()}`
  or `nil`. Templates read `@current_scope.user["name"]`; module calls use
  `@current_scope.scope`.

  A cookie whose session, user, company, or tenant no longer proves out is
  dropped: the request falls through as unauthenticated.
  """
  def fetch_current_scope(conn, _opts) do
    session_user = get_session(conn, @session_key)
    impersonation = get_session(conn, @impersonation_key)

    case current_scope_from(session_user, impersonation) do
      %{scope: %Scope{}} = current_scope ->
        assign(conn, :current_scope, current_scope)

      nil ->
        conn
        |> assign(:session_expired, not is_nil(get_session(conn, @session_key)))
        |> maybe_clear_stale_session()
        |> assign(:current_scope, nil)
    end
  end

  defp maybe_clear_stale_session(conn) do
    if get_session(conn, @session_key), do: configure_session(conn, drop: true), else: conn
  end

  @doc """
  Redirects unauthenticated requests to the login screen. A dropped live
  session surfaces Belimbing's session-expired notice; a fresh anonymous
  visit is redirected silently.
  """
  def require_authenticated(conn, _opts) do
    if conn.assigns[:current_scope] do
      conn
    else
      conn
      |> maybe_put_return_to()
      |> maybe_put_session_expired_flash()
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  defp maybe_put_session_expired_flash(conn) do
    if conn.assigns[:session_expired] do
      put_flash(conn, :session_expired, "expired")
    else
      conn
    end
  end

  defp maybe_put_return_to(conn) do
    if conn.method == "GET" do
      put_session(conn, @return_to_key, conn.request_path)
    else
      conn
    end
  end

  @doc "Redirects authenticated requests away from the login screen."
  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns[:current_scope] do
      conn |> redirect(to: ~p"/dashboard") |> halt()
    else
      conn
    end
  end

  @doc """
  Requires a live Authz allow for `capability`. Denied requests redirect to
  the dashboard; UI hiding is not this plug's job.
  """
  def require_capability(conn, capability) when is_binary(capability) do
    case conn.assigns[:current_scope] do
      %{actor: actor} ->
        case Authz.can(actor, capability) do
          %Decision{allowed: true} ->
            conn

          %Decision{} ->
            conn
            |> put_flash(:error, @denied_message)
            |> redirect(to: ~p"/dashboard")
            |> halt()
        end

      _ ->
        conn
        |> maybe_put_return_to()
        |> redirect(to: ~p"/")
        |> halt()
    end
  end

  @doc "Whether the rehydrated scope lists `capability` among its effective allows."
  defdelegate allowed?(current_scope, capability), to: Bilimbi.Base.UI

  # ------------------------------------------------------------------
  # LiveView on_mount
  # ------------------------------------------------------------------

  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/dashboard")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope do
      current_scope = socket.assigns.current_scope
      user_id = current_scope.actor.id

      if Phoenix.LiveView.connected?(socket) do
        User.subscribe_notifications(current_scope.scope, user_id)
      end

      socket =
        Phoenix.LiveView.attach_hook(
          socket,
          :user_notifications_live_subscriber,
          :handle_info,
          fn
            {:notification_event, _event}, socket ->
              Phoenix.LiveView.send_update(
                Bilimbi.Core.User.Web.NotificationBellComponent,
                id: "topbar-notification-bell"
              )

              {:cont, socket}

            _other, socket ->
              {:cont, socket}
          end
        )

      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  def on_mount({:require_capability, capability}, _params, _session, socket)
      when is_binary(capability) do
    actor = socket.assigns.current_scope.actor

    case Authz.can(actor, capability) do
      %Decision{allowed: true} ->
        {:cont, socket}

      %Decision{} ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, @denied_message)
         |> Phoenix.LiveView.redirect(to: ~p"/dashboard")}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign(
      socket,
      :current_scope,
      current_scope_from(session[@session_key], session[@impersonation_key])
    )
  end

  defp current_scope_from(
         %{
           "session_id" => session_id,
           "user_id" => user_id,
           "company_id" => company_id
         },
         impersonation
       )
       when is_binary(session_id) and session_id != "" and is_integer(user_id) and user_id > 0 and
              is_integer(company_id) and company_id > 0 do
    with {:ok, %Entry{} = entry} <- Session.fetch_session(session_id),
         true <- entry.user_id == user_id,
         {:ok, tenant_id} <- Company.fetch_tenant_id_for_company(company_id),
         {:ok, %Scope{} = scope} <- Tenancy.scope(tenant_id),
         {:ok, %Summary{} = user} <- User.get_user(scope, company_id, user_id) do
      actor = Authz.actor(:user, user.id, scope, company_id)
      %{allowed: allowed} = Authz.effective_capabilities(actor)

      %{
        user: presentation_user(user, scope),
        scope: scope,
        actor: actor,
        capabilities: allowed,
        impersonator: extract_impersonator(impersonation),
        operator_company_missing: operator_company_missing?(scope)
      }
    else
      _ -> nil
    end
  end

  defp current_scope_from(_session_user, _impersonation), do: nil

  # Belimbing's status bar warns only on the operator tenant when that tenant
  # has no primary company. Failures other than "not provisioned" stay quiet:
  # a missing fixture table must not paint a setup warning.
  defp operator_company_missing?(%Scope{} = scope) do
    Scope.platform_operator?(scope) and Company.platform_operator_company() == {:error, :not_provisioned}
  end

  defp extract_impersonator(%{
         "original_user_id" => id,
         "original_user_name" => name
       })
       when is_integer(id) and is_binary(name) do
    %{id: id, name: name}
  end

  defp extract_impersonator(_), do: nil

  defp presentation_user(%Summary{} = user, %Scope{} = scope) do
    %{
      "user_id" => user.id,
      "name" => user.name,
      "email" => user.email,
      "company_id" => user.company_id,
      "company_name" => company_name_for(scope, user.company_id)
    }
  end

  # Display-only company name for the workspace strip. A missing or
  # unreadable company never blocks an otherwise proven session.
  defp company_name_for(_scope, nil), do: nil

  defp company_name_for(%Scope{} = scope, company_id) do
    case Company.get_company(scope, company_id) do
      {:ok, company} -> Company.Summary.display_name(company)
      _ -> nil
    end
  end
end
