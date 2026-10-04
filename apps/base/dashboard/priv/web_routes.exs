[
  %{
    # No capability: the dashboard is every signed-in account's landing page.
    # Each widget and section carries its own capability instead.
    path: "/dashboard",
    live: Bilimbi.Base.Dashboard.Web.IndexLive,
    session: :auth
  }
]
