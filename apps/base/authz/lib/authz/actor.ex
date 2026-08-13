defmodule Bilimbi.Base.Authz.Actor do
  @moduledoc "Validated authorization principal and its explicit tenant/company context."

  alias Bilimbi.Base.Tenancy.Scope

  @enforce_keys [:type, :id, :company_id, :scope]
  defstruct [:type, :id, :company_id, :scope, :acting_for_user_id, attributes: %{}]

  @type principal_type :: :user | :agent
  @type t :: %__MODULE__{
          type: principal_type(),
          id: pos_integer(),
          company_id: pos_integer(),
          scope: Scope.t(),
          acting_for_user_id: pos_integer() | nil,
          attributes: map()
        }

  @spec new!(principal_type(), pos_integer(), Scope.t(), pos_integer(), keyword()) :: t()
  def new!(type, id, %Scope{} = scope, company_id, opts \\ []) do
    actor = %__MODULE__{
      type: type,
      id: id,
      company_id: company_id,
      scope: scope,
      acting_for_user_id: Keyword.get(opts, :acting_for_user_id),
      attributes: Keyword.get(opts, :attributes, %{})
    }

    validate!(actor)
  end

  @spec principal_type(t()) :: String.t()
  def principal_type(%__MODULE__{type: type}), do: Atom.to_string(type)

  @spec cache_key(t()) :: String.t()
  def cache_key(%__MODULE__{} = actor) do
    Enum.join([principal_type(actor), actor.id, actor.company_id], ":")
  end

  defp validate!(%__MODULE__{} = actor) do
    unless actor.type in [:user, :agent],
      do: raise(ArgumentError, "authorization actor type must be :user or :agent")

    positive_id!(actor.id, :id)
    positive_id!(actor.company_id, :company_id)

    if actor.type == :agent do
      positive_id!(actor.acting_for_user_id, :acting_for_user_id)
    end

    unless is_map(actor.attributes), do: raise(ArgumentError, "actor attributes must be a map")

    actor
  end

  defp positive_id!(value, _field) when is_integer(value) and value > 0, do: value

  defp positive_id!(_value, field),
    do: raise(ArgumentError, "#{field} must be a positive integer")
end
