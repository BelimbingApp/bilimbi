defmodule Bilimbi.Core.Company.Summary do
  @moduledoc """
  Stable read model for presenting a tenant-owned company.
  """

  @enforce_keys [:id, :tenant_id, :name, :code, :status]
  defstruct [:id, :tenant_id, :name, :code, :status, :legal_name]

  @type t :: %__MODULE__{
          id: pos_integer(),
          tenant_id: pos_integer(),
          name: String.t(),
          code: String.t(),
          status: String.t(),
          legal_name: String.t() | nil
        }

  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{legal_name: legal_name, name: name}) do
    if present?(legal_name), do: legal_name, else: name
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
