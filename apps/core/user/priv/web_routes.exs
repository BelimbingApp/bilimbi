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
    # No capability: this is the signed-in account's own profile, and
    # Belimbing guards it with authentication alone. The landing-page field
    # is separately governed by base.settings.user.manage on its definition.
    path: "/settings/profile",
    live: Bilimbi.Core.User.Web.ProfileLive,
    session: :auth
  }
]
