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
  }
]
