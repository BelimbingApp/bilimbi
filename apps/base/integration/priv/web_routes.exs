[
  %{
    path: "/system/api-exchanges",
    live: Bilimbi.Base.Integration.Web.IndexLive,
    session: :auth,
    capability: "admin.system.outbound-exchange.list"
  },
  %{
    path: "/system/api-exchanges/:id",
    live: Bilimbi.Base.Integration.Web.ShowLive,
    session: :auth,
    capability: "admin.system.outbound-exchange.list"
  }
]
