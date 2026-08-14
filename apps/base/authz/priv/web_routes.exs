[
  %{
    path: "/authz/roles",
    live: Bilimbi.Base.Authz.Web.RolesIndexLive,
    session: :auth,
    capability: "admin.authz.role.list"
  },
  %{
    path: "/authz/roles/:id",
    live: Bilimbi.Base.Authz.Web.RoleShowLive,
    session: :auth,
    capability: "admin.authz.role.view"
  }
]
