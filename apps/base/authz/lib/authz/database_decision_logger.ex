defmodule Bilimbi.Base.Authz.DatabaseDecisionLogger do
  @moduledoc false

  @behaviour Bilimbi.Base.Authz.DecisionLogger

  require Logger

  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.Resource
  alias Bilimbi.Base.Repo

  @impl true
  def log(%Actor{} = actor, capability, resource, %Decision{} = decision, context)
      when is_binary(capability) and is_map(context) do
    attributes = %{
      company_id: actor.company_id,
      actor_type: Actor.principal_type(actor),
      actor_id: actor.id,
      acting_for_user_id: actor.acting_for_user_id,
      capability: String.downcase(capability),
      resource_type: resource && resource.type,
      resource_id: resource_id(resource),
      allowed: decision.allowed,
      reason_code: Atom.to_string(decision.reason),
      applied_policies: decision.policies,
      context: json_safe(context),
      trace_id: trace_id(context),
      occurred_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }

    case attributes |> DecisionLog.changeset() |> Repo.insert() do
      {:ok, _log} ->
        :ok

      {:error, changeset} ->
        Logger.error("authorization decision log rejected: #{inspect(changeset.errors)}")
        :ok
    end
  rescue
    error ->
      Logger.error("authorization decision log persistence failed: #{Exception.message(error)}")
      :ok
  end

  defp resource_id(nil), do: nil
  defp resource_id(%Resource{id: nil}), do: nil
  defp resource_id(%Resource{id: id}), do: to_string(id)

  defp trace_id(context) do
    case Map.get(context, :trace_id) || Map.get(context, "trace_id") do
      nil -> nil
      value -> value |> to_string() |> String.slice(0, 12)
    end
  end

  defp json_safe(value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: value

  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {json_key(key), json_safe(nested_value)} end)
  end

  defp json_safe(value), do: inspect(value)

  defp json_key(key) when is_binary(key), do: key
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: inspect(key)
end
