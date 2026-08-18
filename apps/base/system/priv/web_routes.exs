[
  %{
    path: "/system/info",
    live: Bilimbi.Base.System.Web.InfoLive,
    session: :auth,
    capability: "admin.system.info.view"
  }
]
