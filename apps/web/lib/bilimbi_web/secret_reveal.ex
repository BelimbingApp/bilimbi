defmodule BilimbiWeb.SecretReveal do
  @moduledoc """
  Reauthentication and audit edge for displaying one stored encrypted setting.

  The capability must be granted explicitly, directly or through a role that
  names it; a `grant_all` role does not confer stored-secret reveal.
  Every attempted reveal records the outcome before plaintext can leave here.
  """

  @behaviour Bilimbi.Base.Settings.SecretRevealService

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.Scope, as: SettingScope
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User
  alias BilimbiWeb.RateLimit

  @capability "base.settings.secret.view"

  @impl true
  def available?(%{scope: %Scope{} = scope}) do
    case Scope.actor(scope) do
      %Actor{type: :user, impersonator_id: nil} ->
        Authz.explicitly_allowed?(scope, @capability) and Authz.can(scope, @capability).allowed

      _ ->
        false
    end
  end

  def available?(_), do: false

  @impl true
  def reveal(%{scope: %Scope{} = scope} = current_scope, key, setting_scope, password)
      when is_binary(key) and is_binary(password) do
    actor = Scope.actor(scope)
    result = attempt(current_scope, key, setting_scope, password, actor)

    case audit(scope, actor, key, setting_scope, result) do
      {:ok, _} -> result
      {:error, _} -> {:error, :audit_unavailable}
    end
  end

  defp attempt(current_scope, key, setting_scope, password, %Actor{} = actor) do
    throttle_key = {:stored_secret_reveal, Scope.tenant_id(current_scope.scope), actor.user_id}

    cond do
      not available?(current_scope) ->
        {:error, :forbidden}

      not stored_encrypted?(current_scope.scope, key, setting_scope) ->
        {:error, :not_found}

      RateLimit.attempt_allowed?(throttle_key) != :allow ->
        {:error, :throttled}

      true ->
        case User.confirm_password(current_scope.scope, actor.company_id, actor.user_id, password) do
          :ok ->
            RateLimit.reset(throttle_key)
            value = Settings.get(key, setting_scope)
            {:ok, if(is_binary(value), do: value, else: Jason.encode!(value))}

          {:error, _reason} ->
            RateLimit.record_attempt(throttle_key)
            {:error, :invalid_password}
        end
    end
  end

  defp stored_encrypted?(scope, key, setting_scope) do
    case Settings.definition(key) do
      %Definition{encrypted: true, editable: editable, capability: capability}
      when is_binary(editable) ->
        (is_nil(capability) or Authz.can(scope, capability).allowed) and
          Settings.get(key, setting_scope) not in [nil, ""]

      _ ->
        false
    end
  end

  defp audit(scope, %Actor{} = actor, key, setting_scope, result) do
    {scope_type, scope_id} = SettingScope.database_identity(setting_scope)

    Audit.record_action(scope, %{
      company_id: actor.company_id,
      actor_type: "user",
      actor_id: actor.user_id,
      event: "settings.secret.reveal",
      payload: %{
        "setting_key" => key,
        "scope_type" => scope_type || "global",
        "scope_id" => scope_id,
        "result" => if(match?({:ok, _}, result), do: "succeeded", else: "refused")
      },
      is_retained: true,
      occurred_at: NaiveDateTime.utc_now()
    })
  rescue
    # A missing actions table is the same pre-canonical / unavailable store
    # state MutationCapture and UserAuth tolerate for best-effort trails.
    # Reveal cannot be best-effort: without a durable row the value stays in.
    error in Postgrex.Error ->
      if match?(%{postgres: %{code: :undefined_table}}, error) do
        {:error, :audit_unavailable}
      else
        reraise error, __STACKTRACE__
      end
  end
end
