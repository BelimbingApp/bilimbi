defmodule Bilimbi.Core.Address.GridTables do
  @moduledoc """
  What Core Address puts in the grid catalog: `addresses` with their
  country, and the attachment links from companies and employees to their
  addresses. Core Address depends on Company, Employee and Geonames, so it
  is the module that names all three.
  """

  alias Bilimbi.Core.Address.Grid.AddressesSource
  alias Bilimbi.Core.Address.Grid.Edges

  @doc false
  def tables do
    %{
      tables: [
        %{
          id: "addresses",
          record_kind: "core/address",
          label: "Addresses",
          capability: "admin.address.list",
          source: AddressesSource,
          key: "id",
          label_field: "label",
          time_field: "created_at",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "label", label: "Label", type: :string},
            %{id: "line1", label: "Line 1", type: :string},
            %{id: "line2", label: "Line 2", type: :string},
            %{id: "locality", label: "Locality", type: :string},
            %{id: "postcode", label: "Postcode", type: :string},
            %{id: "country_iso", label: "Country code", type: :string},
            %{id: "phone", label: "Phone", type: :string},
            %{id: "verification_status", label: "Verification", type: :string},
            %{id: "created_at", label: "Created", type: :datetime}
          ],
          links: [
            %{
              id: "country",
              label: "Country",
              to: "countries",
              kind: :one,
              on: {"country_iso", "iso"}
            },
            %{
              id: "addresses",
              label: "Addresses",
              from: "companies",
              to: "addresses",
              kind: :many,
              via: {Edges, :company_addresses}
            },
            %{
              id: "primary_address",
              label: "Primary address",
              from: "companies",
              to: "addresses",
              kind: :one,
              via: {Edges, :company_primary_address}
            },
            %{
              id: "addresses",
              label: "Addresses",
              from: "employees",
              to: "addresses",
              kind: :many,
              via: {Edges, :employee_addresses}
            }
          ]
        }
      ]
    }
  end
end
