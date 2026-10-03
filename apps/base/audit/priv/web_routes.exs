[
  %{
    path: "/audit/actions",
    live: Bilimbi.Base.Audit.Web.ActionsLive,
    session: :auth,
    capability: "admin.audit.log.list"
  },
  %{
    path: "/audit/mutations",
    live: Bilimbi.Base.Audit.Web.MutationsLive,
    session: :auth,
    capability: "admin.audit.log.list"
  },
  %{
    embed: "record.history",
    live_component: Bilimbi.Base.Audit.Web.RecordHistory,
    capability: "admin.audit.log.list"
  },
  # Catalogue capability offers the widget. Leaving it off the embed keeps a
  # card that is already on the page mounted after the grant is removed; the
  # panel then skips the read.
  %{
    embed: "dashboard.activity",
    live_component: Bilimbi.Base.Audit.Web.DashboardActivityPanel
  }
]
