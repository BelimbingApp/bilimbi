# External agent HTTP API (version 1)

ChatGPT also connects through the [MCP adapter](mcp.md). It uses the same
Agent API and bearer edge with a separate resource-bound authorization-code
grant. Native device connections continue to use this API directly.

Give a client the server address once. Discovery is
`GET /.well-known/oauth-authorization-server` (RFC 8414) and
`GET /.well-known/bilimbi` (API base, version, server name and public client ID).
URLs come from the configured Endpoint URL rather than an untrusted Host header.
The server name is that configured server's hostname.

1. `POST /oauth/device_authorization` with `client_id=bilimbi-native` and
   `agent_id=harness/model-ver-effort` returns a device code, user code,
   verification URI, ten-minute lifetime and polling interval.
2. Show that code and URI to the person. They sign in, check the code and
   stated agent, set an end date and approve or refuse on `/oauth/device`.
3. Poll `POST /oauth/token` with `client_id`, `device_code`, and
   `grant_type=urn:ietf:params:oauth:grant-type:device_code`. Respect
   `authorization_pending` and the increasing interval on `slow_down`.
4. Send the returned opaque access token as `Authorization: Bearer …`, plus
   `X-Bilimbi-Agent-Id` and `X-Bilimbi-Run-Id` on each API request.
   A missing, repeated or malformed header never refuses the call: it is
   recorded as not stated and flagged on the connection like a changed ID.
5. Rotate credentials with `POST /oauth/token`, `grant_type=refresh_token`,
   `client_id` and `refresh_token`. Replace the stored refresh token on success.
   Reusing an old refresh token revokes the connection. Never retry rotation
   blindly when a response is lost; start device sign-in again.

Machine endpoints accept URL-encoded or JSON objects and refuse multipart
uploads; files stay in the harness. Token responses use
`Cache-Control: no-store`. No client secret, cookies, impersonation or
caller-supplied person/tenant/company identity authorizes API requests.
The native client permits plain HTTP at the owner's direction for this stage,
an intentional departure from the RFC transport requirement. Production ChatGPT
MCP connections and plugin export require the configured public HTTPS URL.

- `GET /api/v1/search?q=words`: `{result: [...]}`. Optional `limit` (1–50),
  `kind` (`read` or `write`) and `include_unavailable` (`true` or `false`)
  follow the foundation search options.
- `GET /api/v1/operations/:key`: operation description and schemas.
- `GET /api/v1/guides/:key`: guide text.
- `POST /api/v1/operations/:key/call`: `{input: {...}}`; success retains the
  foundation's `{result, meta}` representation.

- `POST /api/v1/plans`: `{operations: [{key, input}, ...]}`. Returns `valid`,
  per-operation `results` with validated changes or field errors, the exact
  operations, and `meta.content_notice`. A valid plan also returns `plan_code`
  and `expires_at`. No company or employee record is written by this call.
- `POST /api/v1/plans/commit`: `{plan_code, operations}` with the same ordered
  operations and inputs. Returns `results` with created records and absolute
  Bilimbi `url` values. All writes, mutation audits and code consumption commit
  atomically. Codes are single use and bound to the person and connection.
  Invalid, tampered, expired, reused or stale codes return 409; revalidation
  failures return 422 `plan_rejected` with per-operation errors. Re-plan and
  obtain a fresh review when inputs or the preview change. On a lost commit
  response, verify records through read operations before attempting new writes.
  Bilimbi does not verify the person's go; the native client enforces it locally.
  A dry run also deletes this tenant's plan rows that expired over a day ago.

Errors carry `error`; invalid input also carries field errors (422), capability
refusals return 403, missing operations/records return 404, unauthenticated
requests return 401. Calling a write directly answers `writes_not_enabled` (409).
Metadata converts `{:refused, reason}` to `{refused: reason}` for JSON.

Every API/OAuth response uses Base Integration's incoming recorder, including
refused credentials. It stores operation, status, duration, person, connection,
stated agent, run and request trace, without request/result bodies or secrets.
The server assigns a 12-character trace (the compatible audit column’s size)
and returns `X-Bilimbi-Trace-Id`; the exchange correlation and audit trace use
that exact same value.
The bearer edge seals the person and facet; the dispatcher checks live Authz
and the module handler passes that scope to its own facade. Platform and
access-control permissions stay unavailable, writes use a bound plan and the company switch, queue
delegation and workflow human actions refuse a facet.

Standards: [RFC 8628](https://www.rfc-editor.org/rfc/rfc8628),
[RFC 8414](https://www.rfc-editor.org/rfc/rfc8414).
