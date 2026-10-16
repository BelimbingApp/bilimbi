[
  %{
    path: "/contacts",
    live: Bilimbi.Core.Person.Web.IndexLive,
    session: :auth,
    capability: "admin.person.list"
  },
  %{
    path: "/contacts/new",
    live: Bilimbi.Core.Person.Web.CreateLive,
    session: :auth,
    capability: "admin.person.create"
  },
  %{
    path: "/contacts/:id",
    live: Bilimbi.Core.Person.Web.ShowLive,
    session: :auth,
    capability: "admin.person.view"
  }
]
