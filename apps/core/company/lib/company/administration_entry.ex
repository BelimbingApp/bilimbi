defmodule Bilimbi.Core.Company.AdministrationEntry do
  @moduledoc """
  UI-safe Company facts for an administration index row.

  This deliberately excludes registration identifiers, scope activities,
  metadata, and persistence details. Consumers needing a Company detail
  record must use the separate public detail API instead of making this
  list row wider by accident.
  """

  alias Bilimbi.Core.Company.Schema

  @enforce_keys [:id, :name, :code, :status, :primary?]
  defstruct [
    :id,
    :name,
    :code,
    :legal_name,
    :status,
    :jurisdiction,
    :parent_id,
    :parent_name,
    :primary?
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          name: String.t(),
          code: String.t(),
          legal_name: String.t() | nil,
          status: String.t(),
          jurisdiction: String.t() | nil,
          parent_id: pos_integer() | nil,
          parent_name: String.t() | nil,
          primary?: boolean()
        }

  @spec from_query_result({Schema.t(), String.t() | nil, boolean()}) :: t()
  def from_query_result({%Schema{} = company, parent_name, primary?}) do
    %__MODULE__{
      id: company.id,
      name: company.name,
      code: company.code,
      legal_name: company.legal_name,
      status: company.status,
      jurisdiction: company.jurisdiction,
      parent_id: company.parent_id,
      parent_name: parent_name,
      primary?: primary?
    }
  end
end
