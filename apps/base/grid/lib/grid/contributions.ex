defmodule Bilimbi.Base.Grid.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  # The grid page shows nothing of its own: every table on it is read under
  # the capability its owning module declared for it, and the catalog a
  # person sees holds only the tables they may read. Saved views are the
  # account's own settings, as saved workspace layouts are.
  @impl true
  def contributions do
    %{
      settings: %{
        definitions: %{
          "ui.grid.views" => %{
            type: :array,
            scopes: [:user],
            default: [],
            label: "Saved grid views",
            help:
              "The grid views this account saved, each with a slug, a label, a table and its columns, lenses, zoom, sort and filters.",
            capability: "base.settings.user.manage"
          },
          "ui.grid.shared_views" => %{
            type: :array,
            scopes: [:company],
            default: [],
            label: "Shared grid views",
            help:
              "The grid views shared with every account of the company, in the same shape as an account's own.",
            capability: "base.settings.company.manage"
          }
        },
        runtime_claims: []
      },
      menu: [
        %{
          id: "grid",
          label: "Grid",
          icon: "table-cells",
          route: "/grid",
          order: 110
        }
      ]
    }
  end
end
