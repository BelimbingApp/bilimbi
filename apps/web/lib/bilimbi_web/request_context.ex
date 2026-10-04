defmodule BilimbiWeb.RequestContext do
  @moduledoc """
  Applies the per-process locale and audit context for one HTTP request or
  LiveView.

  `BilimbiWeb.UserAuth` calls `apply/2` after it has rehydrated who is signed
  in. Anonymous requests use the global locale. The language is put on the
  shared UI Gettext backend, which is the only catalogue the host renders.
  """

  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.DateTime, as: BaseDateTime
  alias Bilimbi.Base.Locale
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.UI.DateTimeDisplay
  alias Bilimbi.Core.Address

  @gettext_backend Bilimbi.Base.UI.Gettext

  @doc """
  Sets locale, timestamp display, and audit context for this process.

  A LiveView socket is returned with the navigation hook that keeps the
  recorded URL current. A connection is unchanged apart from those process
  stores.
  """
  def apply(current_scope, %Plug.Conn{} = conn) do
    apply_locale(current_scope)
    put_audit_context(current_scope, conn)
    conn
  end

  def apply(current_scope, %Phoenix.LiveView.Socket{} = socket) do
    apply_locale(current_scope)
    put_audit_context(current_scope, socket)
    follow_page_url(socket, current_scope)
  end

  # A LiveView process handles many navigations; each one's URL is the
  # `url` of what is recorded while the page is shown. The hook needs a
  # routed root socket, which is where `handle_params` runs.
  defp follow_page_url(%{router: router} = socket, current_scope)
       when not is_nil(router) and not is_nil(current_scope) do
    Phoenix.LiveView.attach_hook(socket, :audit_context_url, :handle_params, fn _params,
                                                                                uri,
                                                                                socket ->
      AuditContext.put(%{AuditContext.get() | url: uri})
      {:cont, socket}
    end)
  end

  defp follow_page_url(socket, _current_scope), do: socket

  defp apply_locale(nil) do
    put_gettext_locale(Locale.resolve(nil, locale_bootstrap()).language)
    DateTimeDisplay.put(BaseDateTime.display(nil))
  end

  defp apply_locale(%{
         user: %{"user_id" => user_id, "company_id" => company_id},
         scope: %Scope{} = scope,
         shell_preferences: shell_preferences
       }) do
    SettingsScope.user(user_id, company_id, Scope.tenant_id(scope))
    |> Locale.resolve(locale_bootstrap())
    |> then(&put_gettext_locale(&1.language))

    # Timestamp display policy resolves in the same per-process lifecycle as
    # the locale, so no user's mode or company zone leaks into another
    # request or LiveView process (#459). The scope already carries the one
    # resolved snapshot; re-resolving it here would read the same rows twice.
    DateTimeDisplay.put(shell_preferences)
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

  # Captured mutations and recorded actions record who acted (ADR 0013), and
  # from where: the trail exists to tell a developer's own work from a
  # command run through their stolen or hijacked session. Resolved in the
  # same per-process lifecycle as the locale; an anonymous request records
  # the guest default rather than a stale actor from a previous request.
  # Under impersonation the actor is the account acted as and the
  # impersonator is the operator behind the session, so every row names both.
  defp put_audit_context(nil, _source), do: AuditContext.put(nil)

  defp put_audit_context(
         %{user: %{"user_id" => _} = user, scope: %Scope{} = scope, actor: actor} = current_scope,
         source
       ) do
    AuditContext.put(
      struct!(
        %AuditContext{
          actor_type: Atom.to_string(actor.type),
          actor_id: actor.id,
          impersonator_id: impersonator_id(current_scope),
          company_id: user["company_id"],
          tenant_id: Scope.tenant_id(scope),
          trace_id: Logger.metadata()[:request_id]
        },
        request_facts(source)
      )
    )
  end

  defp put_audit_context(_current_scope, _source), do: AuditContext.put(nil)

  defp request_facts(%Plug.Conn{} = conn) do
    %{
      ip_address: conn.remote_ip |> :inet.ntoa() |> to_string(),
      url: Plug.Conn.request_url(conn),
      user_agent: Plug.Conn.get_req_header(conn, "user-agent") |> List.first()
    }
  end

  # A LiveView process serves no HTTP request. The socket's connect info
  # names the client's address and agent (the endpoint asks the transport
  # for both); the page URL arrives per navigation through the
  # `handle_params` hook attached at mount. There is no request id to
  # trace once the socket is connected, so `trace_id` is only what the
  # disconnected render's request left in the Logger metadata.
  defp request_facts(%Phoenix.LiveView.Socket{} = socket) do
    %{
      ip_address: socket |> connect_info(:peer_data) |> peer_ip(connect_info(socket, :x_headers)),
      user_agent: connect_info(socket, :user_agent)
    }
  end

  defp connect_info(%{parent_pid: nil} = socket, key),
    do: Phoenix.LiveView.get_connect_info(socket, key)

  defp connect_info(_child_socket, _key), do: nil

  defp peer_ip(%{address: address}, headers) when is_tuple(address) do
    address
    |> BilimbiWeb.ForwardedFor.client_address(headers || [])
    |> :inet.ntoa()
    |> to_string()
  end

  defp peer_ip(_peer_data, _headers), do: nil

  defp impersonator_id(%{impersonator: %{id: id}}) when is_integer(id) and id > 0, do: id
  defp impersonator_id(_current_scope), do: nil

  defp put_gettext_locale(language) do
    Gettext.put_locale(@gettext_backend, language)
  end
end
