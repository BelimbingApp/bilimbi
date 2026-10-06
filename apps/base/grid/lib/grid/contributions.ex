defmodule Bilimbi.Base.Grid.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  # The grid has no page of its own: a list page hosts it, and every table
  # a column walks to is read under the capability its owning module
  # declared. What an account arranged on a list is its own setting, as its
  # dashboard layout is.
  @impl true
  def contributions do
    %{
      settings: %{
        definitions: %{
          "ui.grid.page_columns" => %{
            type: :array,
            scopes: [:user],
            default: [],
            label: "List columns",
            help:
              "The columns, lenses and row density this account last arranged on each list page, one entry per page.",
            capability: "base.settings.user.manage"
          }
        },
        runtime_claims: []
      }
    }
  end
end
