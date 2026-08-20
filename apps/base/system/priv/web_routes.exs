[
  %{
    path: "/system/info",
    live: Bilimbi.Base.System.Web.InfoLive,
    session: :auth,
    capability: "admin.system.info.view"
  },
  %{
    path: "/system/localization",
    live: Bilimbi.Base.System.Web.LocalizationLive,
    session: :auth,
    capability: "admin.system.localization.manage"
  },
  %{
    path: "/system/menu-inspector",
    live: Bilimbi.Base.System.Web.MenuInspectorLive,
    session: :auth,
    capability: "admin.system.menu-inspector.view"
  }
]
