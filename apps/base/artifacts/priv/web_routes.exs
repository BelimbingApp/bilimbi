[
  %{
    path: "/pdf/render/:token",
    controller: Bilimbi.Base.Artifacts.Web.RenderController,
    action: :show,
    log: false,
    session: :none,
    verb: :get
  }
]
