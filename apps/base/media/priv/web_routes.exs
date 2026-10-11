[
  %{
    path: "/media/assets/:id/stream",
    controller: Bilimbi.Base.Media.Web.AssetController,
    action: :show,
    session: :none
  },
  %{
    path: "/media/attachments/:public_id",
    controller: Bilimbi.Base.Media.Web.AttachmentController,
    action: :show,
    session: :auth
  }
]
