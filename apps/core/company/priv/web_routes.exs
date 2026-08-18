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
    path: "/companies/:id",
    live: Bilimbi.Core.Company.Web.ShowLive,
    session: :auth,
    capability: "admin.company.view"
  }
]
