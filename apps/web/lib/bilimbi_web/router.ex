defmodule BilimbiWeb.Router do
  use BilimbiWeb, :router

  import BilimbiWeb.UserAuth,
    only: [
      fetch_current_scope: 2,
      require_authenticated: 2,
      redirect_if_authenticated: 2,
      require_capability: 2
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
    plug :put_root_layout, html: {BilimbiWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => @content_security_policy
    }

    plug :fetch_current_scope
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :ensure_company_list do
    plug :require_authenticated
    plug :require_capability, "admin.company.list"
  end

  pipeline :ensure_company_view do
    plug :require_authenticated
    plug :require_capability, "admin.company.view"
  end

  pipeline :ensure_user_list do
    plug :require_authenticated
    plug :require_capability, "admin.user.list"
  end

  pipeline :ensure_user_view do
    plug :require_authenticated
    plug :require_capability, "admin.user.view"
  end

  pipeline :ensure_user_create do
    plug :require_authenticated
    plug :require_capability, "admin.user.create"
  end

  pipeline :ensure_user_update do
    plug :require_authenticated
    plug :require_capability, "admin.user.update"
  end

  pipeline :ensure_employee_list do
    plug :require_authenticated
    plug :require_capability, "admin.employee.list"
  end

  pipeline :ensure_employee_view do
    plug :require_authenticated
    plug :require_capability, "admin.employee.view"
  end

  pipeline :ensure_employee_create do
    plug :require_authenticated
    plug :require_capability, "admin.employee.create"
  end

  pipeline :ensure_employee_update do
    plug :require_authenticated
    plug :require_capability, "admin.employee.update"
  end

  pipeline :ensure_employee_type_list do
    plug :require_authenticated
    plug :require_capability, "admin.employee-type.list"
  end

  pipeline :ensure_employee_type_create do
    plug :require_authenticated
    plug :require_capability, "admin.employee-type.create"
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

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_company_list]

    live_session :companies_index,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.company.list"}}
      ] do
      live "/companies", CompanyLive.Index
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_company_view]

    live_session :companies_show,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.company.view"}}
      ] do
      live "/companies/:id", CompanyLive.Show
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_user_list]

    live_session :users_index,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.user.list"}}
      ] do
      live "/users", UserLive.Index
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_user_create]

    live_session :users_new,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.user.create"}}
      ] do
      live "/users/new", UserLive.Form, :new
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_user_view]

    live_session :users_show,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.user.view"}}
      ] do
      live "/users/:id", UserLive.Show
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_user_update]

    live_session :users_edit,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.user.update"}}
      ] do
      live "/users/:id/edit", UserLive.Form, :edit
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_employee_list]

    live_session :employees_index,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.employee.list"}}
      ] do
      live "/employees", EmployeeLive.Index
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_employee_create]

    live_session :employees_new,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.employee.create"}}
      ] do
      live "/employees/new", EmployeeLive.Form, :new
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_employee_view]

    live_session :employees_show,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.employee.view"}}
      ] do
      live "/employees/:id", EmployeeLive.Show
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_employee_update]

    live_session :employees_edit,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.employee.update"}}
      ] do
      live "/employees/:id/edit", EmployeeLive.Form, :edit
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_employee_type_list]

    live_session :employee_types_index,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.employee-type.list"}}
      ] do
      live "/employee-types", EmployeeTypeLive.Index
    end
  end

  scope "/", BilimbiWeb do
    pipe_through [:browser, :ensure_employee_type_create]

    live_session :employee_types_new,
      on_mount: [
        {BilimbiWeb.UserAuth, :require_authenticated},
        {BilimbiWeb.UserAuth, {:require_capability, "admin.employee-type.create"}}
      ] do
      live "/employee-types/new", EmployeeTypeLive.Form, :new
    end
  end

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
