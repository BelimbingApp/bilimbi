[
  %{
    path: "/system/schedule",
    live: Bilimbi.Base.Schedule.Web.IndexLive,
    session: :auth,
    capability: "admin.system.schedule.view"
  }
]
