defmodule Bilimbi.Core.User.ActorVerifier do
  @moduledoc """
  Core User's answer to whether a queued job may still act for its user.

  The account must still exist in the actor's company, and that company must
  not be archived, as the request edge requires. A job queued under impersonation also needs the borrowed durable
  session to still belong to the impersonated account: leaving impersonation
  or signing out ends it. A job the user queued for themselves outlives their
  own sign-out.
  """

  @behaviour Bilimbi.Base.Tenancy.ActorVerifier

  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Session.Entry
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User

  @impl true
  def verify_actor(%Scope{} = scope) do
    %Actor{type: :user} = actor = Scope.actor(scope)

    with :ok <- company_not_archived(actor.company_id),
         {:ok, _user} <- User.get_user(scope, actor.company_id, actor.user_id) do
      impersonation_in_progress(actor)
    end
  end

  defp company_not_archived(company_id) do
    case Company.fetch_tenant_id_for_company(company_id) do
      {:error, :company_archived} -> {:error, :company_archived}
      _live_or_absent -> :ok
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
