[
  %{
    path: "/system/performance",
    live: Bilimbi.Base.Perf.Web.IndexLive,
    session: :auth,
    capability: "admin.system.perf.view",
    operator: true
  },
  %{
    embed: "dashboard.performance",
    live_component: Bilimbi.Base.Perf.Web.DashboardHealthPanel,
    capability: "admin.system.perf.view"
  }
]
