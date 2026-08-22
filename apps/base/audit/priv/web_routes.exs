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
  }
]
