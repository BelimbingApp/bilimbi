# Base Integration

General exchange observability and outgoing HTTP transport. Domain modules own
request meaning, response parsing, retries and user-facing outcomes. API adapters
own authentication and call the inbound recorder after dispatch. Business writes
continue to use the ordinary mutation audit independently of exchange logging.

Administration → API Exchanges lists incoming and outgoing exchanges, with
host/path/operation, HTTP status, outcome, person/agent and inclusive UTC date filters, URL
pagination and the shared flexible table. Each exchange opens a read-only detail
page. Bodies and headers are absent by default; payload inspection is explicit.

## Public API

```elixir
Integration.request(scope, %{system: "partner", operation: "items.fetch",
  owner_type: "domain/orders", owner_id: order_id},
  method: :get, url: url)

# Installation-wide reference-data traffic has no tenant/person.
Integration.request_system(%{system: "geonames", operation: "reference.download"},
  method: :get, url: url, into: File.stream!(destination, [:write]))

# API adapter calls once after dispatch, including refused and failed requests
# for which it has resolved a tenant scope. Authentication remains at that edge.
Integration.record_incoming(scope, %{
  method: "PATCH", endpoint: "/api/companies/17", operation: "company.update",
  response_status: 403, duration_ms: 12,
  connection_id: "connection-id", agent_id: "agent-id", run_id: "run-id"
})
```

`record_incoming_system/1` logs calls whose credentials could not resolve a tenant,
with null tenant/person and operator-only visibility. Connection/agent/run IDs
accept strings or integers (stored as strings).

An omitted method or duration remains unknown; a missing status without an
error class records the `unknown` outcome. An operation key supplies the
endpoint when there is no HTTP path, rather than inventing a URL.

`record_incoming/2` returns `{:ok, exchange_id}` or a validation error. Its
person, impersonator and tenant are derived from the sealed scope; supplied
person/tenant values cannot override them. Identifiers for connection, agent
and run are neutral strings supplied by the authenticated adapter.
`request/3` and `request_system/2` preserve Req's response/error tuples and
streaming options. Retry is disabled by default. Callers may supply an explicit
Req retry policy; one row describes the complete logical gateway call (the
legacy retry_count field is zero because attempts are not instrumented).
Only transport exceptions are converted to error tuples; malformed options and
programming failures propagate. A logging failure raises: the caller must not
mistake it for permission to repeat a command already delivered remotely.

`list_page/2`, `get_exchange/2`, `payload/2` and `delete_exchange/2` accept a
validated scope and enforce permissions on every call. Ordinary tenants can
inspect/delete only their own rows. The platform-operator scope may inspect
all rows, including anonymous system traffic and null-owned legacy exchanges;
operator status does not bypass capabilities. The list and detail API return
metadata maps and never expose the persistence schema or retained payloads.

## Privacy and retention

Credentials in URL userinfo, every query string and fragments are removed.
Do not put secrets in path segments or observational identifiers. Raw error
messages are not persisted. Legacy endpoints are sanitized when read.

Explicit `retain_payload: true` opts into bounded structured previews only.
Authorization, cookies, API keys, passwords, credentials, signature and
secret/token-like keys are recursively redacted. String values are omitted,
including under otherwise innocent keys, because unstructured values can
contain credentials. Numbers, booleans and JSON structure remain inspectable.
Binary/text bodies are omitted; previews over 32 KiB record only their omission.
Payload reads redact again, including adopted legacy rows.

The separately granted capabilities retain Belimbing's durable keys for both
directions: `admin.system.outbound-exchange.list`,
`admin.system.outbound-exchange.payload.view`, and
`admin.system.outbound-exchange.delete`. Auditor and system-viewer roles receive
only list permission. These are tenant-usable capabilities, not operator-only.

The existing Schedule framework runs daily payload retention. The global
operator setting `integration.payload_retention_days` defaults to 30 days and
is editable through Settings. Pruning clears headers, bodies, trace data,
metadata and preview bookkeeping, preserving exchange metadata. It never
creates another payload copy in Audit. Gateway/recorder writes and retention
are machine measurements and silence capture at those precise call sites;
manual deletion stays audited. `Exchange.__audit_redacted_fields__/0` prevents
that audit row from becoming a second payload inspection surface.

## Database port

The baseline matches Belimbing migrations `0100_01_19_000001` and
`0100_01_19_000004`, independently recorded by the pinned Laravel-generated
fixture. It preserves `base_integration_outbound_exchanges`, every existing
column/index, varchar IDs, JSON (not JSONB), nullable tenant ownership and
second-precision timestamps. A separate Bilimbi-only migration adds direction
(default outgoing for adopted rows), method/host/path and person/connection/
agent/run attribution. Keeping the durable relation name permits adoption
without moving existing exchanges; the public API and UI name the general log.
The schema contract's baseline verifies before adoption; added columns are
optional there so an unmodified Belimbing database can be adopted.

OAuth token storage and subject-command admission/rate limiting remain later
ports. The agent HTTP API is a consumer of this recorder, not part of this module.
