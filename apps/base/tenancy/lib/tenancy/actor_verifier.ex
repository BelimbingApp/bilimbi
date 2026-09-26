defmodule Bilimbi.Base.Tenancy.ActorVerifier do
  @moduledoc """
  Re-proves a delegated user actor before a queued job runs as them.

  A job enqueued with `Bilimbi.Base.Queue.enqueue_for/3` can run days after
  the request that proved its user. Base cannot read accounts or sessions, so
  the module that owns accounts implements this behaviour and contributes it
  under the `:actor_verifier` key (ADR 0016). Exactly one may be installed.
  With none, `Bilimbi.Base.Tenancy.Authentication.resume/2` refuses every
  delegated actor.

  `verify_actor/1` receives the rebuilt scope, whose actor is a user. It
  answers `:ok` only when the account still exists in the actor's company
  and, for an actor with an `impersonation_session_id`, that session still
  borrows the account. It must not require the user's own session: signing
  out does not cancel work the user queued.
  """

  alias Bilimbi.Base.Tenancy.Scope

  @callback verify_actor(Scope.t()) :: :ok | {:error, atom()}
end
