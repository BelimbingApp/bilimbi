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
  }
]
