[
  %{
    path: "/users/new",
    live: Bilimbi.Core.User.Web.FormLive,
    session: :auth,
    capability: "admin.user.create"
  },
  %{
    path: "/users/:id",
    live: Bilimbi.Core.User.Web.ShowLive,
    session: :auth,
    capability: "admin.user.view"
  },
  %{
    path: "/users/:id/edit",
    live: Bilimbi.Core.User.Web.FormLive,
    session: :auth,
    capability: "admin.user.update"
  },
  %{
    path: "/settings/profile",
    live: Bilimbi.Core.User.Web.ProfileLive,
    session: :auth
  },
  %{
    # Self-service password change for signed-in account.
    path: "/settings/password",
    live: Bilimbi.Core.User.Web.PasswordLive,
    session: :auth
  },
  %{
    # Self-service appearance preference for signed-in account.
    path: "/settings/appearance",
    live: Bilimbi.Core.User.Web.AppearanceLive,
    session: :auth
  },
  %{
    # No capability: notifications belong to the signed-in account, and
    # Belimbing guards it with authentication alone.
    path: "/notifications",
    live: Bilimbi.Core.User.Web.NotificationsLive,
    session: :auth
  },
  %{
    path: "/admin/system/database-queries",
    live: Bilimbi.Core.User.Web.DatabaseQueriesLive.Index,
    session: :auth,
    capability: "admin.system.database-table.list"
  },
  %{
    path: "/admin/system/database-queries/:slug",
    live: Bilimbi.Core.User.Web.DatabaseQueriesLive.Show,
    session: :auth,
    capability: "admin.system.database-table.list"
  }
]
