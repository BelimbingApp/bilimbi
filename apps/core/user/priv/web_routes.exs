[
  %{
    path: "/users",
    live: Bilimbi.Core.User.Web.IndexLive,
    session: :auth,
    capability: "admin.user.list"
  },
  %{
    path: "/users/new",
    live: Bilimbi.Core.User.Web.FormLive,
    session: :auth,
    capability: "admin.user.create"
  },
  %{
    path: "/users/:id",
    live: Bilimbi.Core.User.Web.ShowLive,
    session: :auth,
    capability: "admin.user.view"
  },
  %{
    path: "/users/:id/edit",
    live: Bilimbi.Core.User.Web.FormLive,
    session: :auth,
    capability: "admin.user.update"
  }
]
