[
  %{
    path: "/system/sessions",
    live: Bilimbi.Base.Session.Web.IndexLive,
    session: :auth,
    capability: "admin.system.session.list",
    operator: true
  },
  # Catalogue capability offers the widget. Leaving it off the embed keeps a
  # card that is already on the page mounted after the grant is removed; the
  # panel then skips the read.
  %{
    embed: "dashboard.sessions",
    live_component: Bilimbi.Base.Session.Web.DashboardStatsPanel
  }
]
