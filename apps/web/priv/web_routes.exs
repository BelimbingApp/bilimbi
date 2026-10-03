[
  %{path: "/", live: BilimbiWeb.LoginLive, session: :anonymous, capability: nil},
  %{
    path: "/forgot-password",
    live: BilimbiWeb.ForgotPasswordLive,
    session: :anonymous,
    capability: nil
  },
  %{
    path: "/reset-password/:token",
    live: BilimbiWeb.ResetPasswordLive,
    session: :anonymous,
    capability: nil
  },
  %{path: "/session", verb: :post, session: :none, capability: nil},
  %{path: "/session", verb: :delete, session: :none, capability: nil},
  %{path: "/admin/impersonate/leave", verb: :post, session: :auth, capability: nil},
  %{path: "/admin/impersonate/:id", verb: :post, session: :auth},
  %{path: "/dashboard", live: BilimbiWeb.DashboardLive, session: :auth, capability: nil}
] ++
  if Mix.env() == :test do
    [
      %{
        webhook: "test-example",
        verify: {BilimbiWeb.WebhookExample, :verify},
        handle: {BilimbiWeb.WebhookExample, :handle}
      }
    ]
  else
    []
  end
