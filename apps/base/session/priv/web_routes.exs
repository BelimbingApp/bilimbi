[
  %{
    path: "/system/sessions",
    live: Bilimbi.Base.Session.Web.IndexLive,
    session: :auth,
    capability: "admin.system.session.list"
  }
]
