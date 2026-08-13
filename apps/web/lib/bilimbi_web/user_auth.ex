defmodule BilimbiWeb.UserAuth do
  @moduledoc """
  Web-edge authentication: session handling, scope propagation, and the
  LiveView `on_mount` hooks for the authenticated shell.

  Business rules stay in the deep modules — `Bilimbi.Core.User` verifies
  credentials, `Bilimbi.Base.Tenancy` proves the tenant. This module only
  carries the proof from the login edge into the Phoenix session and back.

  ## Session shape

  The session stores a small, server-signed map under `"current_user"`: the
  user's `Bilimbi.Core.User.Summary` fields plus the `tenant_id` resolved at
  the login edge. On every request `fetch_current_scope/2` re-proves the
  tenant through `Tenancy.scope/1`, so a soft-deleted tenant ends the
  session's usefulness immediately. User display fields (name, email) are
  presentation data refreshed at each login.

  ## Cross-module seam

  `Bilimbi.Core.Company.fetch_tenant_id_for_company/1` — a public
  company → tenant read for the login edge — is requested on issue #87.
  Until it exists the seam falls back to the platform-operator company,
  which covers the development seed. The fallback is honest about its
  limits (`{:error, :tenant_unavailable}`) rather than guessing.
  """

  import Plug.Conn
  import Phoenix.Controller

  use BilimbiWeb, :verified_routes

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Summary

  @session_key "current_user"
  @return_to_key "user_return_to"
  @login_token_salt "session-login"
  @login_token_max_age 120

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
  Signs a short-lived token carrying the rehydration map for
  `SessionController`. The map — not just the user id — is signed so a
  tampered hidden field cannot smuggle another tenant into the session.
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
  Builds the session map for a freshly authenticated user: summary fields
  plus the tenant resolved through the company seam. This is the one place
  a tenant is resolved from a user; every later request starts from the
  signed session value and re-proves it.
  """
  @spec session_user(Summary.t()) :: {:ok, map()} | {:error, :tenant_unavailable}
  def session_user(%Summary{} = user) do
    with {:ok, tenant_id} <- tenant_id_for_user(user) do
      {:ok,
       %{
         "user_id" => user.id,
         "name" => user.name,
         "email" => user.email,
         "company_id" => user.company_id,
         "company_name" => company_name_for(tenant_id, user.company_id),
         "tenant_id" => tenant_id
       }}
    end
  end

  # Display-only company name for the workspace strip; resolved through the
  # scoped public API once the tenant is proven. A missing or unreadable
  # company never blocks login — the strip just falls back to "Workspace".
  defp company_name_for(tenant_id, company_id) do
    with {:ok, scope} <- Tenancy.scope(tenant_id),
         {:ok, company} <- Company.get_company(scope, company_id) do
      Bilimbi.Core.Company.Summary.display_name(company)
    else
      _ -> nil
    end
  end

  # Belimbing resolves the tenant from the user's current company
  # (TenantContext). Bilimbi's public company → tenant read for the
  # unauthenticated edge is pending (issue #87); until then the development
  # platform-operator company is the only resolvable case.
  defp tenant_id_for_user(%Summary{company_id: nil}), do: {:error, :tenant_unavailable}

  defp tenant_id_for_user(%Summary{company_id: company_id}) do
    cond do
      function_exported?(Company, :fetch_tenant_id_for_company, 1) ->
        case apply(Company, :fetch_tenant_id_for_company, [company_id]) do
          {:ok, tenant_id} -> {:ok, tenant_id}
          _ -> {:error, :tenant_unavailable}
        end

      true ->
        case Company.platform_operator_company() do
          {:ok, %{id: id, tenant_id: tenant_id}} when id == company_id -> {:ok, tenant_id}
          _ -> {:error, :tenant_unavailable}
        end
    end
  end

  # ------------------------------------------------------------------
  # Session lifecycle
  # ------------------------------------------------------------------

  @doc "Stores the signed session map, renews the session, and redirects."
  def log_in_user(conn, session_user, return_to \\ nil) do
    destination = return_to || get_session(conn, @return_to_key) || ~p"/dashboard"

    conn
    |> configure_session(renew: true)
    |> delete_session(@return_to_key)
    |> put_session(@session_key, session_user)
    |> redirect(to: destination)
  end

  @doc "Drops the session entirely and redirects to the login screen."
  def log_out_user(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  # ------------------------------------------------------------------
  # Plugs
  # ------------------------------------------------------------------

  @doc """
  Loads `conn.assigns.current_scope` from the session. The assign is a map
  `%{user: map, scope: Scope.t()}` or `nil`; templates read
  `@current_scope.user.name` and module calls use `@current_scope.scope`.

  A session whose tenant no longer proves out is dropped: the request falls
  through as unauthenticated.
  """
  def fetch_current_scope(conn, _opts) do
    with %{} = session_user <- get_session(conn, @session_key),
         %{"tenant_id" => tenant_id} <- session_user,
         {:ok, %Scope{} = scope} <- Tenancy.scope(tenant_id) do
      assign(conn, :current_scope, %{user: session_user, scope: scope})
    else
      _ ->
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
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      with %{} = session_user <- session[@session_key],
           %{"tenant_id" => tenant_id} <- session_user,
           {:ok, %Scope{} = scope} <- Tenancy.scope(tenant_id) do
        %{user: session_user, scope: scope}
      else
        _ -> nil
      end
    end)
  end
end
