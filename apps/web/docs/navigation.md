# Live navigation

Normal authenticated routes, including the host dashboard, share the
`:authenticated` LiveView session. `BilimbiWeb.DiscoveredRoutes` contributes
these routes as one block so navigation can use the live connection instead
of reloading the document. Authentication is rehydrated on each destination
mount. Anonymous and operator-only routes keep separate session boundaries.

An open page rechecks its session and page permission before each client
event or URL patch, including events handled by Base UI LiveComponents.
A terminated session or removed login sends the page to sign-in with the
expired-session message. Revoking its page permission sends it to the
dashboard with a refusal message before the action runs. Server-triggered
callbacks are outside this boundary. The host refreshes `current_scope` for
the handler; cached presentation flags are not authorization.

[RouteAccess](../lib/bilimbi_web/route_access.ex) owns the hook, route-policy,
and component callback contract. Additional operation permissions use
[LiveAuthorization](../../base/authz/lib/authz/live_authorization.ex).

Session termination also disconnects idle tabs through
[SessionDisconnect](../lib/bilimbi_web/session_disconnect.ex). Sockets carrying
`UserAuth.live_socket_id/1` reconnect and are refused at mount. The next-action
check does not depend on receiving that notification. The
[Session API](../../base/session/lib/session.ex) owns which deletion operations
publish and the notification timing.

The menu and content render together through Base UI. Sharing the session does
not cache the actor's permissions or introduce a separate menu request. The
shell still belongs to the destination view; independently persisting it is a
separate decision, justified only by authenticated navigation measurements.

The disconnected render reuses the HTTP plug's `current_scope` through
`assign_new/3`, avoiding a second session, actor and preference resolution in
the same request. Connected mounts and live navigation resolve identity anew;
a session revoked after the HTML response must fail the connected mount.

Long-poll fallback explicitly disables the transport's code reloader. Otherwise
every poll and event POST recompiles/checks all reloadable packages in development,
even though it is not a page request. Regular HTTP page requests retain the code
reloader, and the existing development file watcher still triggers page reloads.
Manual refresh also compiles edits. This does not disable authentication or origin
checks, and both transports receive the same signed-cookie session configuration.

## Verification

Run the Web discovered-route, dashboard, User form, and operator SQL-console
integration tests. `live_redirect/2` proves that a destination can be mounted
without a fresh HTTP request; tests also cover denied destinations, terminated
sessions and same-view patches with different capabilities.

The pinned LiveView 1.2.9 test client has a `Diff.drop_cids/2` failure when a
live redirect removes the last stateful component (dashboard to a page without
one). The navigation regression therefore runs module pages into the dashboard;
check the reverse direction in a browser as well. Do not change production
components to work around a test-client diff failure.

Browser verification on 2026-09-22 used the local development instance and a
signed-in Edge session. Dashboard → Sessions → Companies → Dashboard emitted
LiveView MOUNT/HANDLE PARAMS messages with no intervening page GET requests.
The final revision's server mount plus parameter handling took about 64 ms,
113 ms and 50 ms respectively while the test suite was running. These are
server timings, not browser paint measurements or production benchmarks.

A subsequent browser-side probe revealed that the existing Edge tab had retained
Phoenix's LongPoll fallback. The absence of page GETs did not establish WebSocket
use. In that tab, redirect-start to navigation-stop measured 480–1,179 ms before
disabling compilation on polls, and 81–162 ms afterwards across Dashboard,
Sessions and Companies. Two animation frames after navigation-stop measured
123–217 ms afterwards; this is a rendering opportunity, not a guaranteed paint
metric. The shell hook itself took 1–3 ms. A fresh tab established WebSocket
successfully. These are small local development samples, not percentile benchmarks
or a controlled PHP/Elixir comparison. Temporary console probes were removed.
