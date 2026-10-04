# Base Session

`Bilimbi.Base.Session` owns the durable session store compatible with
Belimbing's root `sessions` table. It stores an opaque payload and session
metadata without depending on Core User or Phoenix Web.

Existing Laravel payloads are preserved as data but are not assumed to be
readable by the Phoenix session adapter (`BilimbiWeb.UserAuth`). That adapter treats an
unrecognized payload as expired. Session listing never exposes payloads, and
termination refuses to delete the caller's current session ID. The module-owned
admin adapter is `Bilimbi.Base.Session.Web.IndexLive` at `/system/sessions`.
The global operator setting `session.lifetime_minutes` is editable as **Session
lifetime** at `/system/settings`. Its bounds and default are declared in
[`Session.Contributions`](../lib/session/contributions.ex). The Web
authentication edge rejects sessions older than that idle lifetime and refreshes
activity on authenticated requests, user events, and component callbacks at most
once per configured interval (`session.last_activity_touch_minutes`). Mounted views guard events,
URL patches, component callbacks, and background refreshes; background work does
not extend the idle lifetime. Expired requests and mounted callbacks redirect
to sign-in when checked; an idle page has no expiry timer.

The **Prune expired sessions** task uses the same setting for row cleanup.
Review and enable it at `/system/schedule` before expecting scheduled cleanup;
its cadence is declared in `Session.Contributions`, and the enablement and
delivery rules belong to [Base Schedule](../../schedule/docs/README.md).
Authentication expiry does not depend on cleanup running.

## Ending a session

The [Session API documentation](../lib/session.ex) owns the bulk termination
contract and the `subscribe_terminations/0` notification contract. The host's
[Live navigation documentation](../../../web/docs/navigation.md) describes
how session termination affects open pages.

The Web authentication edge calls `touch_session/2` only after validating the
session identity, including authenticated LiveView events and live-patch
navigation. Component-targeted events reach the authenticated host through
Base UI's shared component event wrapper. These use the server-held session
identity, so a continuously used LiveView refreshes activity without requiring
a remount. The `touch_session/2` documentation in `lib/session.ex` owns the
update and audit policy. `session.retention_days` and
`session.last_activity_touch_minutes` are operator settings; the daily
session worker prunes rows whose stored activity is older than that retention
window. Its definition must first be reviewed and enabled under the
[Schedule delivery policy](../../schedule/docs/README.md#time-and-delivery).
Session keeps this lifecycle independent of Web and Core User.
