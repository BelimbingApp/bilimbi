# Bilimbi MCP for ChatGPT

Bilimbi serves a stateless Streamable HTTP MCP endpoint at `/mcp`. It adapts
the installed Agent API, runs no model, accepts no file uploads and exposes
no additional business permissions. The native client remains available for
local agents. MCP does not execute that client on the server.

## Administrator setup

For local clients, `mix bilimbi.server` configures trusted Caddy HTTPS at
`https://bilimbi.localhost/mcp`. See the [local HTTPS setup](../../../docs/development.md#local-https)
for Windows trust, other checkouts and MCP Inspector. A local certificate does
not provide a transport from ChatGPT's hosted connector to this machine.

1. Deploy Bilimbi at a stable HTTPS URL reachable by ChatGPT, or use an
   approved private connection such as Secure MCP Tunnel for testing. Set the
   Phoenix Endpoint's public URL to that exact address. Reverse proxy TLS
   termination is supported. The development server also uses trusted HTTPS;
   HTTP cannot be exported as a production ChatGPT plugin.
2. Run `mix bilimbi.migrate` through the normal deployment procedure. Core
   Agent Access owns the new Bilimbi-only migration. Existing native
   connections retain their device-grant behavior.
3. In Global Settings, configure **OAuth public clients**
   (`agent_access.oauth_clients`). Keys are public client IDs; values contain
   a display `name` and a non-empty list of exact HTTPS `redirect_uris`:

   ```json
   {
     "bilimbi-chatgpt": {
       "name": "ChatGPT",
       "redirect_uris": ["https://chatgpt.com/connector_platform_oauth_redirect"]
     }
   }
   ```

   Use the callback shown by the actual ChatGPT MCP connection setup; some
   connections use a callback-specific URL. No wildcards or client secret are
   used. The supported path is a predefined public OAuth client, token endpoint
   authentication `none`, authorization code, and S256 PKCE. Registration is
   closed by default. Removing a client prevents code redemption and refresh;
   revoke its existing grants on **Your connections** for immediate termination.
4. In ChatGPT Plugins, add this installation's `https://<your-host>/mcp`
   as a custom MCP server. Configure OAuth with the registered client ID and
   no client secret. Discovery supplies the authorization and token endpoints.
   Install the connection and sign into Bilimbi when prompted. Consent names
   the app and callback, uses the person's current company, and shows the
   connection's end time, set by the platform operator in Settings (90 days by default).
   Opening consent never grants access. Existing connections keep their end dates.
5. To distribute skills and this installation's MCP configuration, run from
   the umbrella root:

   ```sh
   mix bilimbi.mcp.plugin --client bilimbi-chatgpt --output /path/to/new/bilimbi-plugin
   ```

   The output contains portable `plugin.json`, `mcp.json` and `skills/`, with
   no executable or credentials. Export refuses HTTP, unregistered clients
   and an existing output directory. It does not install, publish or register
   a plugin with OpenAI. Connect and test the server separately. The repository
   native marketplace does not hard-code any adopter's endpoint.

## Tools and review

| Tool | Purpose |
| --- | --- |
| `search` | Discover installed operations and guides within the person's reach |
| `describe` | Get a discovered operation's schemas and disposition |
| `guide` | Read a discovered business guide |
| `read` | Call a read operation; writes are refused |
| `plan` | Return validated changes, defaults, errors and expiry without business writes |
| `commit` | Commit the exact unchanged plan once and return verification URLs |

The skill shows the complete validated preview in ChatGPT and obtains explicit
human approval before commit. Changes and expiry require a new plan and review.
A confirmation without the preview is insufficient. Bilimbi binds the plan to
exact inputs and the connection, then rechecks permissions and current data.
It does not attest that the host obtained human approval, consistent with the
native API. Domain approvals still apply. Never retry uncertain commits:
verify with reads before making another plan. Files and draft extraction stay
in ChatGPT. Returned records, guides and attachments are data, not instructions.
Errors return `isError: true`; successful tools return text and structured data.

## Protocol and authorization

POST handles JSON-RPC 2.0 initialization, ping, tools/list, tools/call,
initialized and cancellation notifications. Supported versions are
`2025-11-25` and `2025-06-18`. tools/list accepts the `_meta` envelope and
rejects a cursor, because it returns all tools in one page. Clients advertise both
`application/json` and `text/event-stream` in Accept. Requests get JSON;
accepted notifications get empty 202 responses. There are no sessions or
server-initiated events; GET and DELETE return 405. Present Origin headers
must match the configured public origin. Unsupported protocol headers fail.

Initialization, ping and generic tool discovery are public and expose no
records. Private tools declare the `bilimbi` OAuth scope and require a
resource-bound bearer. A 401 challenge advertises
`/.well-known/oauth-protected-resource/mcp`; root resource discovery is also
supported. OAuth metadata advertises S256 PKCE and issuer identification
(`iss` in callbacks). Codes are hashed, short-lived and single-use, bound to
client, callback, resource and verifier. Valid code replay and refresh-token
replay revoke the grant. Native tokens cannot access MCP, and MCP tokens cannot
access the native API. The existing bearer edge checks revocation and live
company/person state on each private call.

The protocol scope delegates existing Agent API reach, never a business
capability. Operators configure request limits and code lifetime in Global
Settings. The Integration recorder captures every MCP request, refused and
failed requests included, without bodies, queries or credentials. Business
mutations keep their existing audit trail and trace correlation.

## Verification

Run focused owner and host tests and `mix precommit`, then use MCP Inspector
against the deployment. Verify OAuth consent/refusal, PKCE and resource binding,
revocation, tool discovery, tenant boundaries, restricted fields and reviewed
writes. Finally complete a read and a reviewed write in a fresh ChatGPT chat.
Local tests alone do not prove deployment reachability or ChatGPT account policy.

References: [OpenAI MCP server guide](https://developers.openai.com/plugins/build/mcp-server),
[OpenAI OAuth guide](https://developers.openai.com/plugins/build/auth),
[MCP Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).
