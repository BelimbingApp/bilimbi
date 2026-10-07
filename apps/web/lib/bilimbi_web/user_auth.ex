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
  identity are never taken from the cookie. HTTP requests, LiveView mounts,
  and root LiveView events rehydrate from live data:

    1. `Session.fetch_session/1` — a terminated row ends the cookie;
    2. the durable row's `user_id` must match the cookie, and its activity
       must satisfy the idle-expiry policy in `apps/base/session/docs/README.md`;
    3. `Company.fetch_tenant_id_for_company/1` then `Tenancy.scope/1`;
    4. `User.get_user/3` must return that user in that company.

  Any miss fails closed and the request is unauthenticated. Once all four
  hold, `Bilimbi.Base.Tenancy.Authentication.sign_in/4` seals the user (and
  any impersonating operator) onto the request's `Scope`, so every module
  call made with `@current_scope.scope` carries an actor it can read with
  `Scope.actor/1` and no caller can assert. Login writes
  a cryptographically strong session id through `Session.put_session/3`
  with an opaque payload; logout calls `Session.delete_session/1` before
  dropping the cookie.

  For connected-page reauthorization, see `BilimbiWeb.RouteAccess`. Session
  termination transport handling belongs to `BilimbiWeb.SessionDisconnect`.

  Once identity is rehydrated, display preferences already carry the resolved
  locale and language. `BilimbiWeb.RequestContext` applies that language to the
  shared UI Gettext backend and the audit context for this process, and does
  not resolve the locale again. Anonymous requests still resolve the global
  locale once. HTTP requests and LiveViews each apply it in their own process
  lifecycle, so no user's language remains in another request or LiveView
  process. Impersonation lives in `BilimbiWeb.Impersonation`.

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
  alias Bilimbi.Base.Locale
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Session.Entry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.DisplayPreferences
  alias Bilimbi.Core.User.Summary
  alias BilimbiWeb.Impersonation
  alias BilimbiWeb.RequestContext

  @session_key "current_user"
  @impersonation_key "impersonation"
  @return_to_key "user_return_to"
  @login_token_salt "session-login"
  @login_token_max_age 120
  # Opaque compatibility payload. Web never interprets session contents.
  @opaque_payload "{}"
  @denied_message "You do not have access to that page."
  @expired_flash "expired"
  # `Phoenix.LiveView.Router.fetch_live_flash/2` reads this cookie. The
  # session cookie itself is dropped, so the notice has to travel separately.
  @live_flash_cookie "__phoenix_flash__"

  @doc false
  def session_key, do: @session_key

  @doc false
  def impersonation_key, do: @impersonation_key

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
        |> put_session(:live_socket_id, live_socket_id(session_id))
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

  # Impersonation updates this same durable row in place. Login is the other caller.
  @doc false
  def persist_durable_session(conn, user_id, company_id, existing_session_id \\ nil) do
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

  @doc false
  def current_session_id(conn) do
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

  @doc """
  The transport topic every live socket of a durable session listens on.

  `Phoenix.LiveView.Socket.id/1` reads it from the cookie session, so a
  `"disconnect"` broadcast on it closes every tab of that session. Base
  Session reports terminations and `BilimbiWeb.SessionDisconnect` sends it.
  """
  @spec live_socket_id(String.t()) :: String.t()
  def live_socket_id(session_id) when is_binary(session_id), do: "session:" <> session_id

  @doc """
  Deletes the durable session row, drops the cookie, and redirects to login.
  Base Session reports the deletion, which disconnects the session's sockets.
  """
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

  # ------------------------------------------------------------------
  # Plugs
  # ------------------------------------------------------------------

  @doc """
  Loads `conn.assigns.current_scope` from live identity. The assign is a map
  `%{user: map, scope: Scope.t(), actor: Authz.Actor.t(), capabilities: [String.t()],
  grant_all: boolean(), impersonator: map | nil, session_identity: map,
  shell_preferences: map, operator_company_missing: boolean()}` or `nil`.
  `capabilities` and `grant_all` are one `effective_capabilities/1` result.
  Templates read
  `@current_scope.user["name"]`; module calls use `@current_scope.scope`.
  `shell_preferences` is the single resolved theme, timestamp display, locale,
  and language snapshot for the request or LiveView process. The shell pin
  list is not part of this assign: the full shell attaches it once at mount.
  A framed LiveView, and a controller that never renders the shell, do not
  query it.

  A cookie whose session, user, company, or tenant no longer proves out is
  dropped: the request falls through as unauthenticated.
  """
  def fetch_current_scope(conn, _opts) do
    session_user = get_session(conn, @session_key)
    impersonation = get_session(conn, @impersonation_key)
    current_scope = current_scope_from(session_user, impersonation, :bootstrap)

    RequestContext.apply(current_scope, conn)

    case current_scope do
      %{scope: %Scope{}} = current_scope ->
        conn
        |> assign(:current_scope, current_scope)
        |> assign(:ui_theme, ui_theme(current_scope))

      nil ->
        conn
        |> assign(:session_expired, not is_nil(get_session(conn, @session_key)))
        |> maybe_clear_stale_session()
        |> assign(:current_scope, nil)
        |> assign(:ui_theme, nil)
    end
  end

  # The root layout stamps `data-theme` only for an explicit light/dark
  # choice; "system" (the default) stamps nothing so the stylesheet's
  # `prefers-color-scheme` block governs (#657).
  defp ui_theme(%{shell_preferences: %{theme: theme}}) when theme in ["light", "dark"], do: theme
  defp ui_theme(_current_scope), do: nil

  defp maybe_clear_stale_session(conn) do
    if get_session(conn, @session_key) do
      conn
      |> store_expired_flash()
      |> configure_session(drop: true)
    else
      conn
    end
  end

  # Store the notice before `configure_session(drop: true)`. A redirect cannot
  # keep it in the session cookie that drop deletes, so a signed LiveView flash
  # cookie carries it to the sign-in screen. A same-request render uses the assign.
  defp store_expired_flash(conn) do
    token = expired_flash_token()

    conn
    |> put_flash(:session_expired, @expired_flash)
    |> register_before_send(fn conn ->
      if conn.status in 300..308 do
        put_resp_cookie(conn, @live_flash_cookie, token,
          max_age: 60,
          path: "/",
          same_site: "Lax"
        )
      else
        conn
      end
    end)
  end

  defp expired_flash_token do
    Phoenix.LiveView.Utils.sign_flash(BilimbiWeb.Endpoint, %{"session_expired" => @expired_flash})
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
      put_flash(conn, :session_expired, @expired_flash)
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
  Requires a string capability, or at least one key in `{:any_of, keys}`,
  from the scope's in-memory allowed list.

  A key already on that list is allowed without another `Authz.can/2`, so an
  allowed page does not write a decision-log row. A key that is absent is
  still evaluated and logged. Denied requests redirect to the dashboard; UI
  hiding is not this plug's job. An open page's later events do not use this
  shortcut: `BilimbiWeb.RouteAccess` re-checks those live.
  """
  def require_capability(conn, capability) do
    case conn.assigns[:current_scope] do
      %{actor: _actor} = current_scope ->
        if gate_allowed?(current_scope, capability) do
          conn
        else
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
    socket = socket |> mount_current_scope(session) |> put_shell_pins(session)

    if socket.assigns.current_scope do
      current_scope = socket.assigns.current_scope

      if Phoenix.LiveView.connected?(socket) do
        Bilimbi.Base.UI.SessionGuard.install(fn activity? ->
          durable_session_valid?(current_scope, activity?)
        end)
      end

      socket =
        socket
        |> Phoenix.LiveView.attach_hook(:durable_session_params, :handle_params, fn
          _params, _uri, socket ->
            if Phoenix.LiveView.connected?(socket),
              do: guard_session(socket, true),
              else: {:cont, socket}
        end)
        |> Phoenix.LiveView.attach_hook(:durable_session_info, :handle_info, fn
          :durable_session_expired, socket ->
            {:halt, expire_socket(socket)}

          _message, socket ->
            guard_session(socket, false)
        end)
        |> Phoenix.LiveView.attach_hook(:durable_session_async, :handle_async, fn
          _name, _result, socket -> guard_session(socket, false)
        end)

      socket =
        Phoenix.LiveView.attach_hook(socket, :durable_session_activity, :handle_event, fn
          _event, _params, socket ->
            guard_session(socket, true)
        end)

      socket =
        Phoenix.LiveView.attach_hook(socket, :component_session_activity, :handle_info, fn
          {Bilimbi.Base.UI.ComponentActivity, :activity}, socket ->
            _ = Session.touch_session(socket.assigns.current_scope.session_identity["session_id"])
            {:halt, socket}

          _message, socket ->
            {:cont, socket}
        end)

      {:cont, BilimbiWeb.ShellPreferences.attach(socket)}
    else
      {:halt, redirect_if_ended(socket, session)}
    end
  end

  def on_mount({:require_capability, capability}, _params, _session, socket) do
    if gate_allowed?(socket.assigns.current_scope, capability) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, @denied_message)
       |> Phoenix.LiveView.redirect(to: ~p"/dashboard")}
    end
  end

  def on_mount(:require_platform_operator, _params, _session, socket) do
    if operator_scope?(socket.assigns.current_scope) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, @denied_message)
       |> Phoenix.LiveView.redirect(to: ~p"/dashboard")}
    end
  end

  # The route gate trusts the allowed list just stored on the scope. A key
  # that is not on it still goes through `Authz.can/2` (via `allowed_now?/2`)
  # so the denial is evaluated and logged. Events on an open page do not use
  # this function; `RouteAccess` re-checks those live.
  defp gate_allowed?(current_scope, requirement) do
    allowed?(current_scope, requirement) or
      capability_allowed?(current_scope[:actor], requirement)
  end

  defp capability_allowed?(_actor, nil), do: false

  defp capability_allowed?(actor, requirement),
    do: Bilimbi.Base.Authz.LiveAuthorization.allowed_now?(actor, requirement)

  # An operator-only screen (#650) requires the actor's tenant to be the platform
  # operator, not merely a capability grant. This mount checks the scope rehydrated
  # for the request; event handlers repeat that mount-proven check at their own
  # guards, and a changed tenant marker takes effect on a fresh authenticated mount.
  defp operator_scope?(%{scope: %Scope{} = scope}), do: Scope.platform_operator?(scope)
  defp operator_scope?(_), do: false

  defp mount_current_scope(socket, session) do
    # The HTTP plug already resolved this request's identity. Reuse it for
    # the disconnected render; a connected mount or live navigation has no
    # conn assigns and must resolve the durable session and permissions anew.
    socket =
      Phoenix.Component.assign_new(socket, :current_scope, fn ->
        current_scope_from(session[@session_key], session[@impersonation_key], :bootstrap)
      end)

    RequestContext.apply(socket.assigns.current_scope, socket)
  end

  @doc false
  def refresh_scope(current), do: refresh_scope(current, true)

  def refresh_scope(%{session_identity: identity, impersonator: impersonator}, activity?)
      when is_boolean(activity?) do
    impersonation =
      if impersonator,
        do: %{"original_user_id" => impersonator.id, "original_user_name" => impersonator.name}

    case current_scope_from(identity, impersonation, nil, activity?) do
      nil -> {:error, :unauthenticated}
      scope -> {:ok, scope}
    end
  end

  # Platform-operator address facts feed one-time locale inference. The
  # resolver touches Company/Address/Geonames, so it runs only while no
  # supported global locale row exists; once inference persists, this stays
  # a single Settings read per request.
  defp locale_bootstrap do
    if Locale.overridden?(nil), do: nil, else: Address.platform_operator_locale_bootstrap()
  rescue
    error in Postgrex.Error ->
      if match?(%{postgres: %{code: :undefined_table}}, error) do
        nil
      else
        reraise error, __STACKTRACE__
      end
  end

  defp current_scope_from(session_user, impersonation, bootstrap_mode, activity? \\ true)

  defp current_scope_from(
         %{
           "session_id" => session_id,
           "user_id" => user_id,
           "company_id" => company_id
         },
         impersonation,
         bootstrap_mode,
         activity?
       )
       when is_binary(session_id) and session_id != "" and is_integer(user_id) and user_id > 0 and
              is_integer(company_id) and company_id > 0 and is_boolean(activity?) do
    with {:ok, %Entry{} = entry} <- Session.fetch_session(session_id),
         true <- entry.user_id == user_id,
         true <- session_active?(entry),
         {:ok, tenant_id} <- Company.fetch_tenant_id_for_company(company_id),
         {:ok, %Scope{} = tenant_scope} <- Tenancy.scope(tenant_id),
         {:ok, %Summary{} = user} <- User.get_user(tenant_scope, company_id, user_id) do
      impersonator = Impersonation.extract_impersonator(impersonation)

      # Every fact above is proven, so this edge is where the scope learns who
      # is signed in. Module code reads that from `Scope.actor/1` and cannot
      # assert it; this is one of the seam's two callers.
      scope =
        Authentication.sign_in(
          tenant_scope,
          user.id,
          company_id,
          Impersonation.impersonation_opts(impersonator, session_id)
        )

      # Session metadata is housekeeping, not a user action. Touch only after
      # this edge has proved the durable session and identity, throttled by the
      # Session setting so ordinary requests do not amplify writes. Background
      # refreshes (`activity?` false) never extend the idle lifetime.
      if activity?, do: Session.touch_session(session_id)

      {:ok, actor} = Authz.scope_actor(scope)
      %{allowed: allowed, grant_all: grant_all} = Authz.effective_capabilities(actor)

      current_scope = %{
        user: presentation_user(user, scope),
        scope: scope,
        actor: actor,
        capabilities: allowed,
        grant_all: grant_all,
        impersonator: impersonator,
        session_identity: %{
          "session_id" => session_id,
          "user_id" => user_id,
          "company_id" => company_id
        },
        operator_company_missing: operator_company_missing?(scope)
      }

      Map.put(
        current_scope,
        :shell_preferences,
        DisplayPreferences.presentation(
          current_scope,
          if(bootstrap_mode == :bootstrap, do: locale_bootstrap(), else: nil)
        )
      )
    else
      _ -> nil
    end
  end

  defp current_scope_from(_session_user, _impersonation, _bootstrap_mode, _activity?), do: nil

  defp put_shell_pins(socket, %{"bilimbi_framed" => true}), do: socket

  defp put_shell_pins(%{assigns: %{current_scope: %{pins: pins}}} = socket, _session)
       when is_list(pins),
       do: socket

  defp put_shell_pins(%{assigns: %{current_scope: current_scope}} = socket, _session)
       when is_map(current_scope) do
    Phoenix.Component.assign(
      socket,
      :current_scope,
      Map.put(current_scope, :pins, shell_pins(current_scope))
    )
  end

  defp put_shell_pins(socket, _session), do: socket

  defp shell_pins(%{scope: %Scope{} = scope}) do
    case BilimbiWeb.PinController.shell_pins(scope) do
      {:ok, pins} -> pins
      {:error, _reason} -> []
    end
  end

  defp shell_pins(_current_scope), do: []

  defp guard_session(socket, activity?) do
    if durable_session_valid?(socket.assigns.current_scope, activity?) do
      {:cont, socket}
    else
      {:halt, expire_socket(socket)}
    end
  end

  defp redirect_if_ended(socket, session) do
    if session[@session_key] do
      expire_socket(socket)
    else
      Phoenix.LiveView.redirect(socket, to: ~p"/")
    end
  end

  defp expire_socket(socket) do
    socket
    |> Phoenix.LiveView.put_flash(:session_expired, @expired_flash)
    |> Phoenix.LiveView.redirect(to: ~p"/")
  end

  defp durable_session_valid?(%{session_identity: identity}, activity?) do
    with {:ok, %Entry{} = entry} <- Session.fetch_session(identity["session_id"]),
         true <- entry.user_id == identity["user_id"],
         true <- session_active?(entry) do
      if activity?, do: Session.touch_session(entry.id)
      true
    else
      _ -> false
    end
  end

  defp session_active?(%Entry{last_activity: last_activity}) do
    lifetime_minutes = Bilimbi.Base.Settings.get("session.lifetime_minutes")
    last_activity >= System.system_time(:second) - lifetime_minutes * 60
  end

  # Belimbing's status bar warns only on the operator tenant when that tenant
  # has no primary company. Failures other than "not provisioned" stay quiet:
  # a missing fixture table must not paint a setup warning.
  defp operator_company_missing?(%Scope{} = scope) do
    Scope.platform_operator?(scope) and
      Company.platform_operator_company() == {:error, :not_provisioned}
  end

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
    case Company.identity(scope, company_id) do
      {:ok, %{display_name: name}} -> name
      _ -> nil
    end
  end
end
