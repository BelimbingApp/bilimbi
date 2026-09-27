[
  %{
    path: "/workspace",
    live: Bilimbi.Base.Tiling.Web.WorkspaceLive,
    session: :auth,
    capability: nil
  },
  %{
    path: "/workspace/shared-layouts",
    live: Bilimbi.Base.Tiling.Web.SharedLayoutsLive,
    session: :auth,
    capability: "ui.workspace.publish"
  },
  %{
    path: "/workspace/shared/:slug",
    live: Bilimbi.Base.Tiling.Web.WorkspaceLive,
    session: :auth,
    capability: nil
  },
  %{
    path: "/workspace/:slug",
    live: Bilimbi.Base.Tiling.Web.WorkspaceLive,
    session: :auth,
    capability: nil
  }
]
