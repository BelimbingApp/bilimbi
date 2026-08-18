defmodule BilimbiWeb.Router do
  use BilimbiWeb, :router

  import BilimbiWeb.UserAuth,
    only: [
      fetch_current_scope: 2,
      require_authenticated: 2,
      redirect_if_authenticated: 2
    ]

  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "base-uri 'self'",
                               "form-action 'self'",
                               "frame-ancestors 'self'",
                               "object-src 'none'",
                               "script-src 'self'",
                               "style-src 'self'",
                               "img-src 'self' data:",
                               "font-src 'self'",
                               "connect-src 'self'"
                             ],
                             "; "
                           )

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Bilimbi.Base.UI.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => @content_security_policy
    }

    plug :fetch_current_scope
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # The homepage is the sign-in screen; authenticated visitors are forwarded
  # to their workspace.
  scope "/", BilimbiWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    live_session :anonymous,
      on_mount: [{BilimbiWeb.UserAuth, :redirect_if_authenticated}] do
      live "/", LoginLive
      live "/forgot-password", ForgotPasswordLive
      live "/reset-password/:token", ResetPasswordLive
    end
  end

  scope "/", BilimbiWeb do
    pipe_through :browser

    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :require_authenticated]

    live_session :authenticated,
      on_mount: [{BilimbiWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive
    end
  end

  @manifest_path Path.expand(
                   "../../../../_build/#{Application.compile_env!(:web, :mix_env)}/bilimbi_routes.exs",
                   __DIR__
                 )
  @external_resource @manifest_path
  require BilimbiWeb.DiscoveredRoutes
  BilimbiWeb.DiscoveredRoutes.inject()

  # Other scopes may use custom stacks.
  # scope "/api", BilimbiWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If you do not have an admins-only section yet, you can
    # use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BilimbiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
