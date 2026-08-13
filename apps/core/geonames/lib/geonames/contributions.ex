defmodule Bilimbi.Core.Geonames.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      menu: [
        %{
          id: "admin.geonames",
          label: "Geonames",
          icon: "globe-alt",
          parent: "admin",
          route: "/geonames",
          capability: "admin.geonames.list",
          order: 50
        },
        %{
          id: "admin.geonames.country",
          label: "Countries",
          parent: "admin.geonames",
          route: "/geonames/countries",
          order: 10
        },
        %{
          id: "admin.geonames.admin1-division",
          label: "Admin1 Divisions",
          parent: "admin.geonames",
          route: "/geonames/admin1",
          order: 20
        },
        %{
          id: "admin.geonames.postcode",
          label: "Postcodes",
          parent: "admin.geonames",
          route: "/geonames/postcodes",
          order: 30
        }
      ],
      authz: %{
        capabilities: ["admin.geonames.view", "admin.geonames.list"],
        roles: %{
          "tenant_owner" => %{
            capabilities: ["admin.geonames.view", "admin.geonames.list"]
          }
        }
      }
    }
  end
end
