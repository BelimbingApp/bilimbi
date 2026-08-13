defmodule Bilimbi.Base.Settings.Scope do
  @moduledoc """
  Explicit scope context for Settings lookup and inheritance.

  User scopes may carry company and tenant context; company scopes may carry
  tenant context. This is the only information used to build the canonical
  user → company → tenant → global lookup chain.
  """

  @enforce_keys [:type, :id]
  defstruct [:type, :id, :company_id, :tenant_id]

  @type type :: :company | :tenant | :user
  @type t :: %__MODULE__{
          type: type(),
          id: pos_integer(),
          company_id: pos_integer() | nil,
          tenant_id: pos_integer() | nil
        }

  @spec company(pos_integer(), pos_integer() | nil) :: t()
  def company(company_id, tenant_id \\ nil) do
    %__MODULE__{
      type: :company,
      id: positive_id!(company_id, :company_id),
      tenant_id: optional_id!(tenant_id, :tenant_id)
    }
  end

  @spec tenant(pos_integer()) :: t()
  def tenant(tenant_id) do
    %__MODULE__{type: :tenant, id: positive_id!(tenant_id, :tenant_id)}
  end

  @spec user(pos_integer(), pos_integer() | nil, pos_integer() | nil) :: t()
  def user(user_id, company_id \\ nil, tenant_id \\ nil) do
    %__MODULE__{
      type: :user,
      id: positive_id!(user_id, :user_id),
      company_id: optional_id!(company_id, :company_id),
      tenant_id: optional_id!(tenant_id, :tenant_id)
    }
  end

  @spec chain(t() | nil) :: [t() | nil]
  def chain(nil), do: [nil]

  def chain(%__MODULE__{type: :tenant} = scope), do: [scope, nil]

  def chain(%__MODULE__{type: :company, tenant_id: tenant_id} = scope) do
    [scope, optional_scope(:tenant, tenant_id), nil] |> Enum.reject(&is_nil_gap?/1)
  end

  def chain(%__MODULE__{type: :user, company_id: company_id, tenant_id: tenant_id} = scope) do
    [scope, optional_scope(:company, company_id), optional_scope(:tenant, tenant_id), nil]
    |> Enum.reject(&is_nil_gap?/1)
  end

  @spec database_identity(t() | nil) :: {String.t() | nil, pos_integer() | nil}
  def database_identity(nil), do: {nil, nil}
  def database_identity(%__MODULE__{type: type, id: id}), do: {Atom.to_string(type), id}

  defp optional_scope(_type, nil), do: :missing
  defp optional_scope(:company, id), do: company(id)
  defp optional_scope(:tenant, id), do: tenant(id)
  defp is_nil_gap?(:missing), do: true
  defp is_nil_gap?(_scope), do: false

  defp positive_id!(value, _field) when is_integer(value) and value > 0, do: value

  defp positive_id!(_value, field),
    do: raise(ArgumentError, "#{field} must be a positive integer")

  defp optional_id!(nil, _field), do: nil
  defp optional_id!(value, field), do: positive_id!(value, field)
end
