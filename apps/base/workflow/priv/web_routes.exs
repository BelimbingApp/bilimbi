[
  %{
    path: "/workflow/reference/:id",
    live: Bilimbi.Base.Workflow.Web.ReferenceLive,
    session: :auth,
    capability: "admin.reference.record.approve"
  }
]
