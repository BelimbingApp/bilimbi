# Live navigation

Normal authenticated routes, including the host dashboard, share the
`:authenticated` LiveView session. `BilimbiWeb.DiscoveredRoutes` contributes
these routes as one block so navigation can use the live connection instead
of reloading the document. Authentication is rehydrated on each destination
mount. Anonymous and operator-only routes keep separate session boundaries.

`BilimbiWeb.RouteAccess` checks each route's declared capability before the
module's mount runs, and again before a URL patch enters a different route.
Search, sort and pagination patches within the same route retain that page's
existing mount policy. The router supplies
a compile-time action key for this lookup; the hook clears that host-only key
before the adapter runs, preserving the existing nil-action adapter contract.
A missing policy fails closed. Modules sharing a LiveView (for example User
create/edit) still have distinct policies. Event authorization remains the
owning module's responsibility.

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
