defmodule Bilimbi.Base.Tenancy.Actor do
  @moduledoc """
  Who a unit of work is performed by, as proven at the edge that began it.

  Read it with `Bilimbi.Base.Tenancy.Scope.actor/1`, never from the struct
  field: the reader verifies the seal, and a scope whose actor was built or
  changed anywhere but the edge raises `Bilimbi.Base.Tenancy.ForgedActorError`.

  There are two kinds:

    * `:user` — a person signed in through Bilimbi's authentication edge, or a
      background job acting for one (`Bilimbi.Base.Queue.enqueue_for/3`).
      `user_id` and `company_id` name the account; `impersonator_id` names the
      operator behind an impersonated session and is `nil` otherwise.
      `impersonation_session_id` is that borrowed session, so a job queued
      during it can prove the impersonation is still in progress when it runs.
    * `:system` — work nobody signed in for: a scheduled job, a seed, a mix
      task, a scope built with `Bilimbi.Base.Tenancy.scope/1`. It carries no
      user and no authority. An operation that must name the person who
      performed it — an approval, an override — refuses it.

      A system actor is anonymous unless a job runs as a **named system
      principal** (`Bilimbi.Base.Queue.enqueue_as_system/4`, ADR 0017). Then
      `system_principal` is the declared name, such as `coating.line_import`, and
      `company_id` is the company the job works in. It holds only the
      capabilities an administrator granted that name for that company. It
      is still never a person: it has no `user_id`, cannot be impersonated,
      and cannot approve.

  The actor is an identity, not a permission. Ask Base Authz whether it may do
  something: `Bilimbi.Base.Authz.can/4` accepts the scope itself.
  """

  @enforce_keys [:type, :seal]
  @derive {Inspect, except: [:seal, :impersonation_session_id]}
  defstruct [
    :type,
    :user_id,
    :company_id,
    :impersonator_id,
    :impersonation_session_id,
    :system_principal,
    :seal
  ]

  @type t ::
          %__MODULE__{
            type: :user,
            user_id: pos_integer(),
            company_id: pos_integer(),
            impersonator_id: pos_integer() | nil,
            impersonation_session_id: String.t() | nil,
            system_principal: nil,
            seal: binary()
          }
          | %__MODULE__{
              type: :system,
              user_id: nil,
              company_id: pos_integer() | nil,
              impersonator_id: nil,
              impersonation_session_id: nil,
              system_principal: String.t() | nil,
              seal: binary()
            }

  @doc "Whether the actor is a signed-in person (or a job acting for one)."
  @spec user?(t()) :: boolean()
  def user?(%__MODULE__{type: type}), do: type == :user

  @doc "Whether the actor is system work that nobody signed in for, named or not."
  @spec system?(t()) :: boolean()
  def system?(%__MODULE__{type: type}), do: type == :system

  @doc "The declared system principal the work runs as, or `nil`."
  @spec system_principal(t()) :: String.t() | nil
  def system_principal(%__MODULE__{type: :system, system_principal: name}), do: name
  def system_principal(%__MODULE__{}), do: nil
end
