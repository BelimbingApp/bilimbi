defmodule Bilimbi.Core.Company.PrimaryCompanyNotProvisionedError do
  @moduledoc """
  Raised when a tenant has no explicit primary-company assignment.
  """

  defexception [:message, :tenant_id]

  @impl true
  def exception(options) do
    tenant_id = Keyword.fetch!(options, :tenant_id)

    %__MODULE__{
      tenant_id: tenant_id,
      message: "tenant #{tenant_id} has no primary company"
    }
  end
end
