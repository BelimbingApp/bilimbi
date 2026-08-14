[
  %{
    path: "/system/settings",
    live: Bilimbi.Base.Settings.Web.GroupLive,
    session: :auth,
    capability: "base.settings.global.manage"
  }
]
