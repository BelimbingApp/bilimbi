defmodule Bilimbi.Base.Tenancy.Scope do
  @moduledoc """
  The validated tenant boundary for one unit of work, and who performs it.

  A scope is constructed once, at the edge, from a live tenant. Every module
  API that reads or writes tenant-owned data takes a scope instead of a raw
  tenant ID, so no module re-resolves the tenant and none can be handed an
  identifier it has not proven.

  A scope cannot exist for a missing or soft-deleted tenant. That is the point:
  operations further in do not carry a `:tenant_not_found` failure mode,
  because the failure is already impossible by the time they run.

  ## The actor

  Every scope carries a `Bilimbi.Base.Tenancy.Actor`. Read it with `actor/1`:

    * A scope built by `Bilimbi.Base.Tenancy.scope/1` or `for_tenant/1` carries
      the **system** actor. That is correct for scheduled work, seeds, and mix
      tasks, and it is all domain code can build.
    * A **user** actor is attached only by Bilimbi's authentication edge, after
      it has proven the session: the Web host's plugs and LiveView `on_mount`
      hooks, and Base Queue when a job enqueued with
      `Bilimbi.Base.Queue.enqueue_for/3` runs. See
      `Bilimbi.Base.Tenancy.Authentication`.

  So a domain operation that must record who performed it — an approver, an
  override — takes that person from `actor/1`, never from its caller's
  arguments, and refuses a system actor. To ask whether the actor may do it,
  pass the scope to `Bilimbi.Base.Authz.can/4`.

  The actor is sealed to its tenant. A struct literal, a struct update, or an
  actor moved onto another tenant's scope makes `actor/1` raise
  `Bilimbi.Base.Tenancy.ForgedActorError`, so an actor cannot be asserted by
  building the data that holds it.
  """

  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.ActorSeal
  alias Bilimbi.Base.Tenancy.Identity

  @enforce_keys [:tenant, :actor]
  defstruct [:tenant, :actor]

  @type t :: %__MODULE__{tenant: Identity.t(), actor: Actor.t()}

  @doc """
  Wraps an already-validated live tenant, performed by the system actor.

  Prefer `Bilimbi.Base.Tenancy.scope/1`, which performs the validation. Use
  this only where a live tenant identity is already in hand, such as inside a
  transaction that has just locked the row.
  """
  @spec for_tenant(Identity.t()) :: t()
  def for_tenant(%Identity{} = tenant),
    do: %__MODULE__{tenant: tenant, actor: ActorSeal.system(tenant)}

  @spec tenant(t()) :: Identity.t()
  def tenant(%__MODULE__{tenant: tenant}), do: tenant

  @spec tenant_id(t()) :: pos_integer()
  def tenant_id(%__MODULE__{tenant: %Identity{id: tenant_id}}), do: tenant_id

  @doc """
  Who performs this unit of work: the signed-in user, or the system.

  This is the one way to read the actor. It verifies the seal the edge gave
  it and raises `Bilimbi.Base.Tenancy.ForgedActorError` for an actor built or
  changed anywhere else.
  """
  @spec actor(t()) :: Actor.t()
  def actor(%__MODULE__{tenant: %Identity{id: tenant_id}, actor: actor}),
    do: ActorSeal.verify!(actor, tenant_id)

  @spec platform_operator?(t()) :: boolean()
  def platform_operator?(%__MODULE__{tenant: %Identity{is_platform_operator: marked?}}),
    do: marked?
end
