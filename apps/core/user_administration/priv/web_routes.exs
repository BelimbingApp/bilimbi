[
  %{
    path: "/users",
    live: Bilimbi.Core.UserAdministration.Web.IndexLive,
    session: :auth,
    capability: "admin.user.list"
  }
]
