[
  %{
    path: "/system/design-library",
    live: Bilimbi.Base.UI.Web.DesignLibraryLive,
    session: :auth,
    capability: "admin.system.design-library.view"
  },
  %{
    path: "/system/design-library/components",
    live: Bilimbi.Base.UI.Web.DesignLibraryComponentsLive,
    session: :auth,
    capability: "admin.system.design-library.view"
  },
  %{
    path: "/system/design-library/design-spec",
    live: Bilimbi.Base.UI.Web.DesignLibraryDesignSpecLive,
    session: :auth,
    capability: "admin.system.design-library.view"
  },
  %{
    path: "/system/design-library/graphic",
    live: Bilimbi.Base.UI.Web.DesignLibraryGraphicLive,
    session: :auth,
    capability: "admin.system.design-library.view"
  }
]
