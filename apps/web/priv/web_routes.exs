[
  %{path: "/", live: BilimbiWeb.LoginLive, session: :anonymous, capability: nil},
  %{path: "/forgot-password", live: BilimbiWeb.ForgotPasswordLive, session: :anonymous, capability: nil},
  %{path: "/reset-password/:token", live: BilimbiWeb.ResetPasswordLive, session: :anonymous, capability: nil},
  %{path: "/session", verb: :post, session: :none, capability: nil},
  %{path: "/session", verb: :delete, session: :none, capability: nil},
  %{path: "/admin/impersonate/leave", verb: :post, session: :auth, capability: nil},
  %{path: "/admin/impersonate/:id", verb: :post, session: :auth, capability: "admin.user.impersonate"},
  %{path: "/dashboard", live: BilimbiWeb.DashboardLive, session: :auth, capability: nil},
  %{path: "/companies", live: BilimbiWeb.CompanyLive.Index, session: :auth, capability: "admin.company.list"},
  %{path: "/companies/:id", live: BilimbiWeb.CompanyLive.Show, session: :auth, capability: "admin.company.view"},
]
