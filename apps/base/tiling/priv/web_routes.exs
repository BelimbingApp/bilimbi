[
  %{
    path: "/workspace",
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
