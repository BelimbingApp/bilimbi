[
  %{
    path: "/authz/roles",
    live: Bilimbi.Base.Authz.Web.RolesIndexLive,
    session: :auth,
    capability: "admin.authz.role.list"
  },
  # Declared before "/authz/roles/:id" on purpose: the parameterised route would
  # otherwise match "create" as an id and render Show for a role that cannot exist.
  %{
    path: "/authz/roles/create",
    live: Bilimbi.Base.Authz.Web.RoleCreateLive,
    session: :auth,
    capability: "admin.authz.role.create"
  },
  %{
    path: "/authz/roles/:id",
    live: Bilimbi.Base.Authz.Web.RoleShowLive,
    session: :auth,
    capability: "admin.authz.role.view"
  },
  %{
    path: "/authz/principal-roles",
    live: Bilimbi.Base.Authz.Web.PrincipalRolesLive,
    session: :auth,
    capability: "admin.authz.principal-role.list"
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
