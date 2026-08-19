# Bilimbi.Base.Dashboard

Widget-based dashboard system. Modules contribute widget definitions through the
`Bilimbi.Base.ModuleRegistry.ContributionProvider` contract under the
`:dashboard` consumer key.

## Public API

- `widgets/0` — all validated, ordered widget definitions
- `fetch_widget/1` — lookup a widget by its contribution id

## Contribution shape

```elixir
def contributions do
  %{
    dashboard: [
      %{
        id: "my.module.widget-id",
        label: "Widget Label",
        size: :small,       # :small | :medium | :large (default :small)
        order: 10,           # display order (default 0)
        capability: "admin.my.list"  # optional capability gate
      }
    ]
  }
end
```

The `Bilimbi.Base.Dashboard.ContributionValidator` validates and orders all
contributed widgets at boot time.

## Rendering

Widget rendering is owned by the dashboard LiveView (`BilimbiWeb.DashboardLive`).
The widget catalogue from `widgets/0` determines which widgets appear and
their order; the LiveView renders built-in widgets directly and can resolve
future widget components by `widget.component` when dynamic rendering is
implemented.
