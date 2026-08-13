[
  %{
    path: "/tenancy/tenants",
    live: Bilimbi.Base.Tenancy.Web.TenantsLive,
    session: :auth,
    capability: "admin.tenancy.tenant.list"
  }
]
