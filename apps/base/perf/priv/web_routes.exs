[
  %{
    path: "/system/performance",
    live: Bilimbi.Base.Perf.Web.IndexLive,
    session: :auth,
    capability: "admin.system.perf.view",
    operator: true
  },
  # Catalogue capability offers the widget. Leaving it off the embed keeps a
  # card that is already on the page mounted after the grant is removed; the
  # panel then skips the read.
  %{
    embed: "dashboard.performance",
    live_component: Bilimbi.Base.Perf.Web.DashboardHealthPanel
  }
]
