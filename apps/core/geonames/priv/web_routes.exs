[
  %{
    path: "/geonames/countries",
    live: Bilimbi.Core.Geonames.Web.CountriesLive,
    session: :auth,
    capability: "admin.geonames.list"
  },
  %{
    path: "/geonames/admin1",
    live: Bilimbi.Core.Geonames.Web.Admin1Live,
    session: :auth,
    capability: "admin.geonames.list"
  },
  %{
    path: "/geonames/postcodes",
    live: Bilimbi.Core.Geonames.Web.PostcodesLive,
    session: :auth,
    capability: "admin.geonames.list"
  }
]
