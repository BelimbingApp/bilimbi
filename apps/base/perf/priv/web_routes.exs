[
  %{
    path: "/system/performance",
    live: Bilimbi.Base.Perf.Web.IndexLive,
    session: :auth,
    capability: "admin.system.perf.view"
  }
]
