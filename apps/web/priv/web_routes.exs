[
  %{path: "/", live: BilimbiWeb.LoginLive, session: :anonymous, capability: nil},
  %{path: "/forgot-password", live: BilimbiWeb.ForgotPasswordLive, session: :anonymous, capability: nil},
  %{path: "/reset-password/:token", live: BilimbiWeb.ResetPasswordLive, session: :anonymous, capability: nil},
  %{path: "/session", verb: :post, session: :none, capability: nil},
  %{path: "/session", verb: :delete, session: :none, capability: nil},
  %{path: "/dashboard", live: BilimbiWeb.DashboardLive, session: :auth, capability: nil},
  %{path: "/companies", live: BilimbiWeb.CompanyLive.Index, session: :auth, capability: "admin.company.list"},
  %{path: "/companies/:id", live: BilimbiWeb.CompanyLive.Show, session: :auth, capability: "admin.company.view"},
  %{path: "/users", live: BilimbiWeb.UserLive.Index, session: :auth, capability: "admin.user.list"},
  %{path: "/users/new", live: BilimbiWeb.UserLive.Form, session: :auth, capability: "admin.user.create"},
  %{path: "/users/:id", live: BilimbiWeb.UserLive.Show, session: :auth, capability: "admin.user.view"},
  %{path: "/users/:id/edit", live: BilimbiWeb.UserLive.Form, session: :auth, capability: "admin.user.update"}
]
