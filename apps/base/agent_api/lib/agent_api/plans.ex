defmodule Bilimbi.Base.AgentApi.Plans do
  @moduledoc """
  A single-use review contract. Only digests are stored, never input or review
  values. The random plan code is hashed at rest and binds the ordered operations,
  exact JSON inputs, tenant, person, signed-in company and OAuth connection.

  Preview calls domain validation without writing business records. Commit locks
  the code, rechecks permissions and the preview, then calls each domain commit
  facade and consumes the code in one transaction. A failed operation rolls back
  all records, audits and code consumption. Changed defaults or reference data
  require a fresh plan. A code proves what was reviewed, not the person's go:
  the native client's review loop obtains that go (ADR 0021).
  """
  import Ecto.Query
  alias Bilimbi.Base.AgentApi.{Dispatcher, Json, Plan}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.{Repo, Settings, Tenancy}
  alias Bilimbi.Base.Tenancy.Scope

  def preview(%Scope{} = scope, operations) do
    with :ok <- shape(operations) do
      results = previews(scope, operations)
      valid? = Enum.all?(results, & &1["valid"])

      if valid? do
        code = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        expires = DateTime.add(now(), Settings.get("agent_api.plan_expiry_seconds"), :second)

        Repo.insert!(%Plan{
          id: code_id(code),
          tenant_id: Scope.tenant_id(scope),
          binding_hash: identity_hash(scope),
          operations_hash: hash(operations),
          preview_hash: hash(results),
          expires_at: expires
        })

        {:ok,
         %{
           "meta" => %{"content_notice" => Dispatcher.content_notice()},
           "valid" => true,
           "plan_code" => code,
           "expires_at" => DateTime.to_iso8601(expires),
           "operations" => operations,
           "results" => results
         }}
      else
        {:ok,
         %{
           "valid" => false,
           "operations" => operations,
           "results" => results,
           "meta" => %{"content_notice" => Dispatcher.content_notice()}
         }}
      end
    end
  end

  def commit(%Scope{} = scope, code, operations) when is_binary(code) and byte_size(code) == 43 do
    with :ok <- shape(operations) do
      Repo.transaction(fn ->
        plan =
          Repo.one(
            from p in Tenancy.scope_query(Plan, scope),
              where: p.id == ^code_id(code),
              lock: "FOR UPDATE"
          )

        check_plan!(plan, scope, operations)
        results = previews(scope, operations)
        unless Enum.all?(results, & &1["valid"]), do: Repo.rollback({:plan_rejected, results})
        unless hash(results) == plan.preview_hash, do: Repo.rollback(:stale_plan)

        committed =
          operations
          |> Enum.with_index()
          |> Enum.map(fn {op, index} ->
            case Dispatcher.commit(operation(op), scope, op["input"]) do
              {:ok, result} ->
                %{
                  "index" => index,
                  "key" => op["key"],
                  "record" => Json.encode(result.record),
                  "path" => result.path
                }

              {:error, reason} ->
                Repo.rollback(
                  {:plan_rejected,
                   [
                     %{
                       "index" => index,
                       "key" => op["key"],
                       "valid" => false,
                       "error" => error(reason)
                     }
                   ]}
                )
            end
          end)

        plan |> Ecto.Changeset.change(used_at: now()) |> Repo.update!()
        %{"results" => committed, "meta" => %{"content_notice" => Dispatcher.content_notice()}}
      end)
    end
  end

  def commit(%Scope{}, _, _), do: {:error, :invalid_plan_code}

  defp shape(operations) do
    if is_list(operations) and
         length(operations) in 1..Settings.get("agent_api.plan_max_operations") and
         Enum.all?(operations, fn op ->
           is_map(op) and Enum.sort(Map.keys(op)) == ["input", "key"] and is_binary(op["key"]) and
             is_map(op["input"])
         end),
       do: :ok,
       else:
         {:error,
          {:invalid_input,
           %{"operations" => ["must be a bounded non-empty list of key/input objects"]}}}
  end

  defp previews(scope, operations) do
    operations
    |> Enum.with_index()
    |> Enum.map(fn {op, index} ->
      case Dispatcher.preview(operation(op), scope, op["input"]) do
        {:ok, result} ->
          %{
            "index" => index,
            "key" => op["key"],
            "valid" => true,
            "preview" => Json.encode(result)
          }

        {:error, reason} ->
          %{"index" => index, "key" => op["key"], "valid" => false, "error" => error(reason)}
      end
    end)
  end

  defp operation(op),
    do: Map.get(ContributionRegistry.consumer!(:agent_api).operations, op["key"])

  defp check_plan!(nil, _, _), do: Repo.rollback(:invalid_plan_code)

  defp check_plan!(plan, scope, operations) do
    cond do
      plan.binding_hash != identity_hash(scope) or plan.operations_hash != hash(operations) ->
        Repo.rollback(:plan_mismatch)

      not is_nil(plan.used_at) ->
        Repo.rollback(:plan_already_used)

      DateTime.compare(plan.expires_at, now()) != :gt ->
        Repo.rollback(:plan_expired)

      true ->
        :ok
    end
  end

  defp identity_hash(scope) do
    actor = Scope.actor(scope)

    hash([
      Scope.tenant_id(scope),
      actor.type,
      actor.user_id,
      actor.company_id,
      actor.impersonator_id,
      actor.impersonation_session_id,
      if(actor.facet, do: actor.facet.connection_id)
    ])
  end

  defp error({:invalid_input, fields}), do: %{"code" => "invalid_input", "fields" => fields}
  defp error({:forbidden, reason}), do: %{"code" => "forbidden", "reason" => to_string(reason)}

  defp error({:rejected, reason}) when is_atom(reason),
    do: %{"code" => "rejected", "reason" => to_string(reason)}

  defp error({:rejected, _}), do: %{"code" => "rejected"}
  defp error(reason) when is_atom(reason), do: %{"code" => to_string(reason)}
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp code_id(code), do: hash(code) |> Base.encode16(case: :lower)
  defp hash(value), do: :crypto.hash(:sha256, :erlang.term_to_binary(canonical(value)))

  defp canonical(value) when is_map(value),
    do: {:object, value |> Enum.sort() |> Enum.map(fn {k, v} -> {k, canonical(v)} end)}

  defp canonical(value) when is_list(value), do: {:array, Enum.map(value, &canonical/1)}
  defp canonical(value), do: value
end
