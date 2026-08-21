defmodule Bilimbi.Core.Company.IndexEntry do
  @moduledoc "Schema-free row for the tenant companies administration index."

  @enforce_keys [:id, :tenant_id, :name, :code, :status, :is_primary]
  defstruct [
    :id,
    :tenant_id,
    :parent_id,
    :parent_name,
    :name,
    :code,
    :status,
    :legal_name,
    :jurisdiction,
    :email,
    :is_primary
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          tenant_id: pos_integer(),
          parent_id: pos_integer() | nil,
          parent_name: String.t() | nil,
          name: String.t(),
          code: String.t(),
          status: String.t(),
          legal_name: String.t() | nil,
          jurisdiction: String.t() | nil,
          email: String.t() | nil,
          is_primary: boolean()
        }

  @doc false
  @spec from_summary(Bilimbi.Core.Company.Summary.t(), String.t() | nil, boolean()) :: t()
  def from_summary(company, parent_name, is_primary?) do
    %__MODULE__{
      id: company.id,
      tenant_id: company.tenant_id,
      parent_id: company.parent_id,
      parent_name: parent_name,
      name: company.name,
      code: company.code,
      status: company.status,
      legal_name: company.legal_name,
      jurisdiction: company.jurisdiction,
      email: company.email,
      is_primary: is_primary?
    }
  end
end
