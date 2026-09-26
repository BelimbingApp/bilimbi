defmodule Bilimbi.Core.User.ActorVerifier do
  @moduledoc """
  Core User's answer to whether a queued job may still act for its user.

  The account must still exist in the actor's company, as the request edge
  requires. A job queued under impersonation also needs the borrowed durable
  session to still belong to the impersonated account: leaving impersonation
  or signing out ends it. A job the user queued for themselves outlives their
  own sign-out.
  """

  @behaviour Bilimbi.Base.Tenancy.ActorVerifier

  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Session.Entry
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User

  @impl true
  def verify_actor(%Scope{} = scope) do
    %Actor{type: :user} = actor = Scope.actor(scope)

    with {:ok, _user} <- User.get_user(scope, actor.company_id, actor.user_id) do
      impersonation_in_progress(actor)
    end
  end

  defp impersonation_in_progress(%Actor{impersonation_session_id: nil}), do: :ok

  defp impersonation_in_progress(%Actor{impersonation_session_id: session_id, user_id: user_id}) do
    case Session.fetch_session(session_id) do
      {:ok, %Entry{user_id: ^user_id}} -> :ok
      _ended -> {:error, :impersonation_ended}
    end
  end
end
