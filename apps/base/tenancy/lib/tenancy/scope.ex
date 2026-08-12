defmodule Bilimbi.Base.Tenancy.Scope do
  @moduledoc """
  The validated tenant boundary for one unit of work.

  A scope is constructed once, at the edge, from a live tenant. Every module
  API that reads or writes tenant-owned data takes a scope instead of a raw
  tenant ID, so no module re-resolves the tenant and none can be handed an
  identifier it has not proven.

  A scope cannot exist for a missing or soft-deleted tenant. That is the point:
  operations further in do not carry a `:tenant_not_found` failure mode,
  because the failure is already impossible by the time they run.

  The struct is deliberately narrow. When authentication lands it grows an
  actor field, and a scope with an actor may then justify promotion to its own
  Base module; today it carries the tenant it was proven from and nothing else.
  """

  alias Bilimbi.Base.Tenancy.Identity

  @enforce_keys [:tenant]
  defstruct [:tenant]

  @type t :: %__MODULE__{tenant: Identity.t()}

  @doc """
  Wraps an already-validated live tenant.

  Prefer `Bilimbi.Base.Tenancy.scope/1`, which performs the validation. Use
  this only where a live tenant identity is already in hand, such as inside a
  transaction that has just locked the row.
  """
  @spec for_tenant(Identity.t()) :: t()
  def for_tenant(%Identity{} = tenant), do: %__MODULE__{tenant: tenant}

  @spec tenant(t()) :: Identity.t()
  def tenant(%__MODULE__{tenant: tenant}), do: tenant

  @spec tenant_id(t()) :: pos_integer()
  def tenant_id(%__MODULE__{tenant: %Identity{id: tenant_id}}), do: tenant_id

  @spec platform_operator?(t()) :: boolean()
  def platform_operator?(%__MODULE__{tenant: %Identity{is_platform_operator: marked?}}),
    do: marked?
end
