[
  %{
    path: "/system/sessions",
    live: Bilimbi.Base.Session.Web.IndexLive,
    session: :auth,
    capability: "admin.system.session.list",
    operator: true
  },
  %{
    embed: "dashboard.sessions",
    live_component: Bilimbi.Base.Session.Web.DashboardStatsPanel,
    capability: "admin.system.session.list"
  }
]
