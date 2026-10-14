defmodule Bilimbi.Core.AgentAccess.Web.PluginLive do
  @moduledoc "Self-service ChatGPT setup; opening this page or downloading software grants no access."
  use Bilimbi.Base.UI, :live_view
  alias Bilimbi.Core.AgentAccess

  # Selecting public configuration and reporting a browser copy do not write business data.
  @write_guard_opt_out ~w(select_client connection_copied)

  def mount(_, _, socket), do: {:ok, assign(socket, :copy_result, nil)}

  def handle_params(params, _uri, socket) do
    endpoint = socket.endpoint
    origin = endpoint.url()

    case AgentAccess.plugin_clients(socket.assigns.current_scope.scope) do
      {:ok, clients} ->
        requested = params["client_id"]
        selected = Enum.find(clients, &(&1.id == requested))
        selected = selected || if(is_nil(requested) and length(clients) == 1, do: hd(clients))
        client_id = if selected, do: selected.id

        {:noreply,
         assign(socket,
           clients: clients,
           client_id: client_id,
           client_form: to_form(%{"client_id" => client_id || ""}, as: :connection),
           origin: origin,
           https?: URI.parse(origin).scheme == "https",
           error: nil,
           copy_result: nil
         )}

      {:error, :person_required} ->
        {:noreply, assign(socket, error: "Use your own account to install the plugin.")}
    end
  end

  def handle_event("select_client", %{"connection" => %{"client_id" => id}}, socket) do
    {:noreply, push_patch(socket, to: ~p"/settings/chatgpt-plugin?#{[client_id: id]}")}
  end

  def handle_event(
        "connection_copied",
        %{"text" => text, "copied" => copied},
        %{assigns: %{error: nil, origin: origin, client_id: client_id}} = socket
      )
      when is_binary(text) and is_boolean(copied) do
    values = [origin <> "/mcp", client_id]
    result = if text in values, do: if(copied, do: :copied, else: :failed)
    {:noreply, assign(socket, :copy_result, result)}
  end

  def handle_event("connection_copied", _, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={nil}>
      <.page variant={:detail}>
        <.header>
          Plugin for ChatGPT
          <:subtitle>
            Install Bilimbi in ChatGPT to work with records using your own account and permissions.
          </:subtitle>
          <:actions>
            <.button id="chatgpt-connections" navigate={~p"/settings/agent-connections"}>Your connections</.button>
          </:actions>
        </.header>
        <.empty_state
          :if={@error}
          id="chatgpt-person-required"
          title="Use your own account"
          reason={@error}
        />
        <div :if={is_nil(@error)} id="chatgpt-setup" class="space-y-4">
          <.card
            id="chatgpt-install"
            inner_class="p-5 sm:p-6"
            role="region"
            aria-labelledby="chatgpt-install-heading"
          >
            <.section_heading id="chatgpt-install-heading" title="Install and sign in" />
            <ol class="list-decimal space-y-2 ps-5 text-sm text-ink">
              <li>
                In ChatGPT, open Plugins and look in your company's tab for Bilimbi. Install the plugin your administrator provides.
              </li>
              <li>
                If your administrator gave you connection details instead, choose the plus button, then Add custom MCP server. Follow the public or LAN/VPN instructions below.
              </li>
              <li>
                Sign in on this Bilimbi installation, review the connection and choose its end date. ChatGPT never needs your Bilimbi password in a message.
              </li>
              <li>
                Start a new chat, select Bilimbi with @, and ask it to find a record you can access.
              </li>
            </ol>
            <p class="mt-4 text-sm text-muted">
              Downloading the plugin does not install it in ChatGPT or approve a connection. You can end access from Your connections.
            </p>
          </.card>

          <.card
            id="chatgpt-details"
            inner_class="p-5 sm:p-6"
            role="region"
            aria-labelledby="chatgpt-details-heading"
          >
            <.section_heading id="chatgpt-details-heading" title="This installation" />
            <.empty_state
              :if={@clients == []}
              id="chatgpt-no-clients"
              title="Administrator setup needed"
              reason="Ask your platform administrator to register ChatGPT under OAuth public clients in Global Settings, using the exact callback shown by ChatGPT."
            />
            <.form
              :if={@clients != []}
              for={@client_form}
              id="chatgpt-client-form"
              phx-change="select_client"
              phx-submit="select_client"
            >
              <.input
                field={@client_form[:client_id]}
                type="select"
                label="OAuth client"
                prompt="Choose the client registered for ChatGPT"
                options={Enum.map(@clients, &{"#{&1.name} (#{&1.id})", &1.id})}
              />
            </.form>
            <div id="chatgpt-copy-values" phx-hook="ClipboardCopy" data-copy-event="connection_copied">
              <.list id="chatgpt-connection-details">
                <:item title="Server URL" id="chatgpt-server-url">
                  <code class="break-all">{@origin}/mcp</code>
                  <.button id="chatgpt-copy-server" type="button" data-copy-text={@origin <> "/mcp"}>Copy</.button>
                </:item>
                <:item :if={@client_id} title="Client ID" id="chatgpt-client-id">
                  <code class="break-all">{@client_id}</code>
                  <.button id="chatgpt-copy-client" type="button" data-copy-text={@client_id}>Copy</.button>
                </:item>
                <:item title="Authentication">OAuth with PKCE (S256); no client secret</:item>
                <:item title="Scope"><code>bilimbi</code></:item>
                <:item title="Authorization URL" id="chatgpt-authorization-url">
                  <code class="break-all">{@origin}/oauth/authorize</code>
                </:item>
                <:item title="Token URL" id="chatgpt-token-url">
                  <code class="break-all">{@origin}/oauth/token</code>
                </:item>
              </.list>
            </div>
            <p
              :if={@copy_result == :copied}
              id="chatgpt-copy-success"
              role="status"
              class="mt-2 text-sm text-muted"
            >
              Copied to clipboard.
            </p>
            <p
              :if={@copy_result == :failed}
              id="chatgpt-copy-failed"
              role="alert"
              class="mt-2 text-sm text-danger-ink"
            >
              Your browser did not allow copying. Select the value and copy it manually.
            </p>
            <.empty_state
              :if={not @https?}
              id="chatgpt-https-required"
              title="HTTPS setup needed"
              reason="Ask your administrator to configure this installation's canonical HTTPS address before downloading the plugin."
            />
            <.empty_state
              :if={@https? and @clients != [] and is_nil(@client_id)}
              id="chatgpt-client-required"
              title="Choose an OAuth client"
              reason="Select the client your administrator registered for ChatGPT to download its plugin configuration."
            />
            <.button
              :if={@https? and @client_id}
              id="chatgpt-download"
              href={~p"/settings/chatgpt-plugin/download?#{[client_id: @client_id]}"}
              variant="primary"
              class="mt-4"
            >Download plugin ZIP</.button>
            <p class="mt-3 text-sm text-muted">
              The ZIP contains Bilimbi's skills and this server's public connection configuration. Give it to your workspace administrator for a company marketplace, or install it through a supported local marketplace. For a private connection, configure Tunnel separately in ChatGPT; the ZIP does not create a tunnel.
            </p>
          </.card>

          <div class="grid gap-4 lg:grid-cols-2">
            <.card
              id="chatgpt-public"
              inner_class="p-5 sm:p-6"
              role="region"
              aria-labelledby="chatgpt-public-heading"
            >
              <.section_heading id="chatgpt-public-heading" title="Public installation" />
              <ol class="list-decimal space-y-2 ps-5 text-sm text-ink">
                <li>
                  Your administrator makes this server's HTTPS address reachable from ChatGPT and registers its OAuth callback in Bilimbi.
                </li>
                <li>
                  In Add custom MCP server, enter the Server URL above. Choose OAuth and the registered Client ID, with no client secret.
                </li>
                <li>Create the plugin, install it, then sign in to Bilimbi when prompted.</li>
              </ol>
              <.link
                id="chatgpt-public-guide"
                href="https://developers.openai.com/plugins/deploy/connect-chatgpt"
                target="_blank"
                rel="noopener noreferrer"
                class="mt-4 inline-block text-sm text-link"
              >OpenAI connection guide</.link>
            </.card>
            <.card
              id="chatgpt-private"
              inner_class="p-5 sm:p-6"
              role="region"
              aria-labelledby="chatgpt-private-heading"
            >
              <.section_heading id="chatgpt-private-heading" title="LAN / VPN installation" />
              <ol class="list-decimal space-y-2 ps-5 text-sm text-ink">
                <li>
                  Your administrator runs OpenAI's Secure MCP Tunnel client on a machine that can reach the Server URL above, and associates the tunnel with your ChatGPT workspace.
                </li>
                <li>
                  In Add custom MCP server, choose Tunnel and select the company tunnel or enter the tunnel ID your administrator provides. Configure the registered OAuth client.
                </li>
                <li>
                  Use the LAN or VPN for Bilimbi sign-in. Your administrator must verify login and token exchange as well as MCP; the tunnel does not automatically expose every OAuth endpoint.
                </li>
              </ol>
              <p class="mt-3 text-sm text-muted">
                Your computer's VPN alone does not give hosted ChatGPT access. The administrator-configured tunnel uses outbound HTTPS. This page does not create or test a tunnel.
              </p>
              <.link
                id="chatgpt-private-guide"
                href="https://developers.openai.com/api/docs/guides/secure-mcp-tunnels"
                target="_blank"
                rel="noopener noreferrer"
                class="mt-4 inline-block text-sm text-link"
              >OpenAI private connection guide</.link>
            </.card>
          </div>
        </div>
      </.page>
    </Layouts.app>
    """
  end
end
