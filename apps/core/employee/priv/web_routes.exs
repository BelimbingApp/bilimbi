[
  %{
    path: "/employees",
    live: Bilimbi.Core.Employee.Web.IndexLive,
    session: :auth,
    capability: "admin.employee.list"
  },
  %{
    path: "/employees/new",
    live: Bilimbi.Core.Employee.Web.FormLive,
    session: :auth,
    capability: "admin.employee.create"
  },
  %{
    path: "/employees/:id",
    live: Bilimbi.Core.Employee.Web.ShowLive,
    session: :auth,
    capability: "admin.employee.view"
  },
  %{
    path: "/employees/:id/edit",
    live: Bilimbi.Core.Employee.Web.FormLive,
    session: :auth,
    capability: "admin.employee.update"
  },
  %{
    path: "/employee-types",
    live: Bilimbi.Core.Employee.Web.TypeIndexLive,
    session: :auth,
    capability: "admin.employee-type.list"
  },
  %{
    path: "/employee-types/new",
    live: Bilimbi.Core.Employee.Web.TypeFormLive,
    session: :auth,
    capability: "admin.employee-type.create"
  },
  %{
    path: "/employee-types/:id/edit",
    live: Bilimbi.Core.Employee.Web.TypeFormLive,
    session: :auth,
    capability: "admin.employee-type.update"
  }
]
