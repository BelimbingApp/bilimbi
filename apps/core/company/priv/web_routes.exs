[
  %{
    path: "/companies/legal-entity-types",
    live: Bilimbi.Core.Company.Web.LegalEntityTypesLive,
    session: :auth,
    capability: "admin.company.list"
  },
  %{
    path: "/companies/department-types",
    live: Bilimbi.Core.Company.Web.DepartmentTypesLive,
    session: :auth,
    capability: "admin.company.list"
  },
  %{
    path: "/companies/:id/departments",
    live: Bilimbi.Core.Company.Web.DepartmentsLive,
    session: :auth,
    capability: "admin.company.view"
  },
  %{
    path: "/companies/:id/relationships",
    live: Bilimbi.Core.Company.Web.RelationshipsLive,
    session: :auth,
    capability: "admin.company.view"
  },
  %{
    path: "/companies",
    live: Bilimbi.Core.Company.Web.IndexLive,
    session: :auth,
    capability: "admin.company.list"
  },
  %{
    path: "/companies/create",
    live: Bilimbi.Core.Company.Web.CreateLive,
    session: :auth,
    capability: "admin.company.create"
  },
  %{
    path: "/setup/platform-operator",
    live: Bilimbi.Core.Company.Web.PlatformOperatorSetupLive,
    session: :auth,
    capability: "admin.company.update"
  },
  %{
    path: "/companies/:id",
    live: Bilimbi.Core.Company.Web.ShowLive,
    session: :auth,
    capability: "admin.company.view"
  }
]
