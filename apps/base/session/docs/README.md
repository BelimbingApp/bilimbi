# Base Session

`Bilimbi.Base.Session` owns the durable session store compatible with
Belimbing's root `sessions` table. It stores an opaque payload and session
metadata without depending on Core User or Phoenix Web.

Existing Laravel payloads are preserved as data but are not assumed to be
readable by a future Phoenix session adapter. That adapter must treat an
unrecognized payload as expired. Session listing never exposes payloads, and
termination refuses to delete the caller's current session ID. The module-owned
admin adapter is `Bilimbi.Base.Session.Web.IndexLive` at `/system/sessions`.
The global operator setting `session.lifetime_minutes` defaults to 120 minutes
of idle time. The Web authentication edge rejects older sessions and refreshes
activity on each user interaction at second precision. Mounted views guard events,
URL patches, component callbacks, and background refreshes; background work does
not extend the idle lifetime. Base Schedule prunes expired rows every five
minutes using the same setting.

## Ending a session

The [Session API documentation](../lib/session.ex) owns the bulk termination
contract and the `subscribe_terminations/0` notification contract. The host's
[Live navigation documentation](../../../web/docs/navigation.md) describes
how session termination affects open pages.
