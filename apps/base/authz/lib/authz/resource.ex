defmodule Bilimbi.Base.Authz.Resource do
  @moduledoc "Optional resource identity used by tenant and company authorization policies."

  alias Bilimbi.Base.Tenancy.Scope

  @enforce_keys [:type]
  defstruct [:type, :id, :company_id, :scope, attributes: %{}]

  @type t :: %__MODULE__{
          type: String.t(),
          id: String.t() | integer() | nil,
          company_id: pos_integer() | nil,
          scope: Scope.t() | nil,
          attributes: map()
        }

  @spec new!(String.t(), String.t() | integer() | nil, keyword()) :: t()
  def new!(type, id \\ nil, opts \\ []) when is_binary(type) and type != "" do
    company_id = Keyword.get(opts, :company_id)
    scope = Keyword.get(opts, :scope)
    attributes = Keyword.get(opts, :attributes, %{})

    unless is_nil(company_id) or (is_integer(company_id) and company_id > 0),
      do: raise(ArgumentError, "resource company_id must be a positive integer or nil")

    unless is_nil(scope) or match?(%Scope{}, scope),
      do: raise(ArgumentError, "resource scope must be a tenant scope or nil")

    unless is_map(attributes), do: raise(ArgumentError, "resource attributes must be a map")

    %__MODULE__{
      type: type,
      id: id,
      company_id: company_id,
      scope: scope,
      attributes: attributes
    }
  end
end
