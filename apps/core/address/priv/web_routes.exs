[
  %{
    path: "/addresses",
    live: Bilimbi.Core.Address.Web.IndexLive,
    session: :auth,
    capability: "admin.address.list"
  },
  %{
    path: "/addresses/create",
    live: Bilimbi.Core.Address.Web.CreateLive,
    session: :auth,
    capability: "admin.address.create"
  },
  %{
    path: "/addresses/:id",
    live: Bilimbi.Core.Address.Web.ShowLive,
    session: :auth,
    capability: "admin.address.view"
  },
  %{
    embed: "employee.addresses",
    live_component: Bilimbi.Core.Address.Web.EmployeeAddressesPanel
  }
]
