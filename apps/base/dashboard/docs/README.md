# Bilimbi.Base.Dashboard

The dashboard at `/dashboard`. Installed modules contribute its widgets and
sections; this module owns the catalogue, the page and each account's
arrangement. It reads no contributor's data (ADR 0009).

## Public API

- `entries/0` — every validated entry of either placement, ordered
- `widgets/0` — the grid widgets
- `sections/0` — the full-width sections below the grid
- `fetch_widget/1` — look up a grid widget by its contribution id

## Contributing an entry

An entry is two declarations in the module that owns the data, and that module
lists `base/dashboard` in its descriptor dependencies.

The contribution provider says what the entry is:

```elixir
def contributions do
  %{
    dashboard: [
      %{
        id: "my-module-open-orders",       # stored in each account's layout; never rename
        label: "Open orders",
        embed: "dashboard.open-orders",    # the panel that draws it
        placement: :grid,                  # :grid (default) | :section
        size: :small,                      # :small | :medium | :large (default :small)
        order: 60,                         # display order (default 0)
        capability: "admin.order.list",    # optional
        refresh_interval: 60_000           # milliseconds; 0 (default) never refreshes
      }
    ]
  }
end
```

`priv/web_routes.exs` declares the panel under the same key and the same
capability:

```elixir
%{
  embed: "dashboard.open-orders",
  live_component: MyModule.Web.DashboardOrdersPanel,
  capability: "admin.order.list"
}
```

`Bilimbi.Base.Dashboard.ContributionValidator` validates and orders the
contributions at boot. An entry without `embed` fails there. An entry whose
panel is not installed renders the not-installed notice of
`<.discovered_panel>`.

## What a panel receives

The page renders each visible entry with `<.discovered_panel>`, so a panel is
a LiveComponent that gets:

- `id` — the component id; put it on the root element
- `current_scope` — the signed-in scope; read tenant data through
  `current_scope.scope`
- `editing` — `true` while the account is customizing the layout. Withhold
  navigation while it is `true`: the page lays its move and remove controls
  over the panel's top-right corner.
- `connected` — false while the first HTML is rendered. A panel with live
  data waits until this is true before its first read.
- `refresh` — a count that grows by one each time the page refreshes. A panel
  with live data reads again when the count changes; a panel that reads once
  ignores it. `update/2` also runs when only `editing` changes, so do not
  read on every call.

`Bilimbi.Base.Session.Web.DashboardStatsPanel` is the smallest refreshing
panel and `Bilimbi.Core.Company.Web.DashboardStatsPanel` the smallest
read-once one.

## Arrangement

Which entries an account shows, and in what order, is stored per user in the
`ui.dashboard.layout` (widgets) and `ui.dashboard.sections` (sections)
settings, which Core User declares with its other account preferences. An
account with no stored row sees the whole catalogue it is allowed to see.
