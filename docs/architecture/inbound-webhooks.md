# Inbound webhooks

Web owns `POST /webhooks/:identifier`, outside the browser/session/CSRF
pipeline. Ordinary controller routes, including discovered `session: :none`
routes, continue to use the browser pipeline. The reserved `/webhooks`
namespace bypasses Endpoint parsers for all content types; no mounted module
should declare browser routes there.

A module registers callbacks in the plain-data route file named by its
`bilimbi.module.exs` descriptor's `web` field:

```elixir
[
  %{webhook: "example-deliveries",
    verify: {Example.Inbound, :verify},
    handle: {Example.Inbound, :handle}}
]
```

Identifiers contain lowercase ASCII letters, digits, underscores and hyphens,
start with a letter, and have at most 80 characters. They are unique across the
composition. Callback tuples name exported functions. Manifest generation
rejects malformed or duplicate declarations and mixed browser/webhook keys;
host boot refuses missing callbacks. Registrations are compiled into the host
release, so source and Mix are unnecessary at runtime. No runtime registration,
application environment list, or module-to-Web dependency is required.

`verify/1` receives `%{body: binary, headers: [{name, value}], remote_ip: tuple,
method: "POST"}` and returns `{:ok, context}` only after authenticating the
delivery. The body is exactly the received bytes, including whitespace and
arbitrary non-UTF8 bytes. JSON/form decoding happens inside the module after
verification. Header pairs retain duplicate headers so the verifier can reject
ambiguous signatures. Every other return value, exception, throw or exit is a
refusal. `handle/2` receives the same request and verified context; `:ok` accepts
it, and any other outcome refuses it. Callbacks never receive a connection or
choose the HTTP response.

The module owns the signature scheme, encrypted secret definition and lookup,
company/tenant resolution, freshness and replay checks, and idempotent delivery
handling. Keep secrets in encrypted Base Settings and let the Settings UI use
Base UI's secret input. Do not obtain secrets from request parameters, log
request bodies/signatures, or return raw verification errors. Resolve a validated
Tenancy Scope before accessing tenant-owned data. An identifier selects a
handler, never an authenticated tenant. A verifier must authenticate any scope
it resolves. Use a durable, idempotent job enqueue when work needs retries or
must outlive the request. Module APIs enforce their normal actor contracts;
the host does not invent a user or system principal for a machine sender.

The existing operator Settings page provides these global controls, authorized
by `base.settings.global.manage`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `webhooks.max_bytes` | 1048576 | Maximum raw body bytes per registered delivery |
| `webhooks.rate_limit` | 120 | Verified deliveries per handler per window per host node |
| `webhooks.sender_rate_limit` | 120 | Attempts per sender address per handler per window per host node, before verification |
| `webhooks.failure_limit` | 60 | Failed attempts per handler per window audited individually |
| `webhooks.window_ms` | 60000 | Fixed rate window in milliseconds |
| `webhooks.read_timeout_ms` | 15000 | Maximum wait per body read in milliseconds |

Size enforcement counts actual accumulated bytes, including chunked bodies,
without trusting Content-Length. Admission is atomic and has two stages.
Before the body is read, each sender address (the connection's remote IP) has
its own allowance per handler, so one sender cannot exhaust another's. An
attempt whose body is oversized or unreadable, or whose verification fails,
counts against the handler's failure bucket and never against verified
capacity. Only after verification succeeds does a delivery draw from the
handler's verified budget. A flood of unsigned requests therefore cannot cause
a genuine signed delivery from another sender to be refused. Senders behind
one address share its allowance; set `webhooks.sender_rate_limit` at least as
high as a provider's own delivery rate.

A window opens on the first request after the previous one closed. It reads
these settings once and uses them until it closes, so operator changes take
effect from the next window. Limiter state is bounded by registered handlers,
one shared unknown-handler bucket and the senders seen in the open window, all
cleared when the window closes; restarting Web resets windows. Each node has
independent limits; deployments requiring a cluster-wide quota must apply that
quota at ingress. These are protection limits, not durable provider quotas.

Success returns HTTP 202 with `{"status":"accepted"}`. All refusals return
HTTP 403 with `{"error":"delivery_refused"}`, including unknown handlers,
size/rate refusal, verification refusal, and callback failure. No reason,
signature or retry context is exposed. Only POST is routed.

Delivery attempts record unscoped guest `webhook.delivery` Base Audit actions.
An attempt admitted past the sender stage records its own action with the
sender address: accepted, refused by its handler, and the first
`webhooks.failure_limit` failures per handler per window. Rate-limited
attempts, unknown identifiers and failures past that limit write no row per
request; when the window closes, each handler (or the one `unknown` bucket)
gets one action per reason with a `count`, so unauthenticated traffic cannot
force a database write per request. The payload carries the registered
identifier (or `unknown`), a host-owned reason, `succeeded`/`refused` and, on
aggregated actions, `count`; it never stores request bodies, headers, query
strings, callback context, secrets or exception details. Aggregated counts
are held in memory until the window closes and are lost if Web stops first. These
null-tenant records are deliberately absent from tenant-scoped audit listings.
Module-owned business operations retain their own normal scoped audit trail.
Audit storage failure refuses acknowledgement of a per-attempt action; a storage outage cannot itself
produce a durable audit record. A handler may have committed work before the
receipt audit fails, so module idempotency must also tolerate a retry after
work has completed. The host promises receipt acknowledgement, not atomicity
between external side effects and audit storage.

`BilimbiWeb.Webhooks` owns the callback/response contract;
`BilimbiWeb.WebhookParsers` owns parser isolation. The test-only
`BilimbiWeb.WebhookExample` demonstrates exact-byte HMAC verification without
shipping a concrete integration or credentials in production.
