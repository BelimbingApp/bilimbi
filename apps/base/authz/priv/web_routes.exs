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
  },
  %{
    path: "/authz/principal-capabilities",
    live: Bilimbi.Base.Authz.Web.PrincipalCapabilitiesLive,
    session: :auth,
    capability: "admin.authz.principal-capability.list"
  },
  %{
    path: "/authz/decision-logs",
    live: Bilimbi.Base.Authz.Web.DecisionLogsLive,
    session: :auth,
    capability: "admin.authz.decision-log.list"
  }
]
