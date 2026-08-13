# Base Session

`Bilimbi.Base.Session` owns the durable session store compatible with
Belimbing's root `sessions` table. It stores an opaque payload and session
metadata without depending on Core User or Phoenix Web.

Existing Laravel payloads are preserved as data but are not assumed to be
readable by a future Phoenix session adapter. That adapter must treat an
unrecognized payload as expired. Session listing never exposes payloads, and
termination refuses to delete the caller's current session ID. The module-owned
admin adapter is `Bilimbi.Base.Session.Web.IndexLive` at `/system/sessions`.

`terminate_user_sessions/2` is the narrow bulk lifecycle operation for a
trusted caller that has already made its authorization decision. It accepts a
positive durable user ID and a non-empty current session ID, deletes that
user's other matching rows in one statement, and returns only the terminated
count. It neither reads nor returns opaque payloads, and it has no Core User or
Web dependency. The operation joins a caller's existing shared Repo
transaction when present. It terminates rows matched by that statement; it is
not a credential epoch or permanent login lockout, so a session established
outside that serialization can survive or appear later.
