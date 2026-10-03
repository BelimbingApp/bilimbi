# Base Session

`Bilimbi.Base.Session` owns the durable session store compatible with
Belimbing's root `sessions` table. It stores an opaque payload and session
metadata without depending on Core User or Phoenix Web.

Existing Laravel payloads are preserved as data but are not assumed to be
readable by a future Phoenix session adapter. That adapter must treat an
unrecognized payload as expired. Session listing never exposes payloads, and
termination refuses to delete the caller's current session ID. The module-owned
admin adapter is `Bilimbi.Base.Session.Web.IndexLive` at `/system/sessions`.

## Ending a session

The [Session API documentation](../lib/session.ex) owns the bulk termination
contract and the `subscribe_terminations/0` notification contract. The host's
[Live navigation documentation](../../../web/docs/navigation.md) describes
how session termination affects open pages.

The Web authentication edge calls `touch_session/2` only after validating the
session identity, including authenticated LiveView events and live-patch
navigation. Component-targeted events reach the authenticated host through
Base UI's shared component event wrapper. These use the server-held session identity, so a continuously used
LiveView refreshes activity without requiring a remount. It writes at most once
per configured interval and bypasses
audit capture because this is machine housekeeping. `session.retention_days`
and `session.last_activity_touch_minutes` are operator settings; the daily
session worker prunes rows outside that retention window. Session keeps this
lifecycle independent of Web and Core User.
