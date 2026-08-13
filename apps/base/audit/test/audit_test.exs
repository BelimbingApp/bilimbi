defmodule Bilimbi.Base.AuditTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Action
  alias Bilimbi.Base.Audit.Mutation
  alias Bilimbi.Base.Audit.SchemaContract
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Tenancy

  import Bilimbi.Base.Audit.TestFixtures
  import Bilimbi.Base.Tenancy.TestFixtures

  setup do
    create_tenants_table!()
    create_audit_tables!()
    :ok
  end

  test "verifies both table contracts against the compatible temporary tables" do
    assert :ok =
             SchemaVerifier.verify(Repo, SchemaContract.tables(), prefix: temporary_schema!())
  end

  test "records a mutation with jsonb payloads, inet, and a nullable tenant" do
    assert {:ok, %Mutation{} = mutation} =
             Audit.record_mutation(%{
               company_id: 73,
               tenant_id: nil,
               actor_type: "user",
               actor_id: 42,
               auditable_type: "App\\Core\\Company\\Models\\Company",
               auditable_id: "73",
               event: "updated",
               occurred_at: ~N[2026-08-13 03:00:00],
               old_values: %{"name" => "Old"},
               new_values: %{"name" => "New"},
               ip_address: "192.0.2.10"
             })

    refute Map.has_key?(mutation, :__meta__)
    assert mutation.tenant_id == nil
    assert mutation.company_id == 73
    assert mutation.old_values == %{"name" => "Old"}
    assert mutation.new_values == %{"name" => "New"}
    assert mutation.ip_address.address == {192, 0, 2, 10}
    assert mutation.source == "listener"
  end

  test "records an action with jsonb payload, inet, and a nullable tenant" do
    assert {:ok, %Action{} = action} =
             Audit.record_action(%{
               company_id: 73,
               tenant_id: nil,
               actor_type: "console",
               actor_id: 0,
               event: "console.command",
               occurred_at: ~N[2026-08-13 03:01:00],
               payload: %{"command" => "mix test"},
               ip_address: "192.0.2.11",
               is_retained: true
             })

    refute Map.has_key?(action, :__meta__)
    assert action.tenant_id == nil
    assert action.payload == %{"command" => "mix test"}
    assert action.ip_address.address == {192, 0, 2, 11}
    assert action.is_retained
  end

  test "lists mutations and actions for the scope and excludes other tenants and null-tenant rows" do
    insert_tenant!(%{id: 41})
    insert_tenant!(%{id: 42, is_platform_operator: false})

    {:ok, owner} = Tenancy.scope(41)

    assert {:ok, owned_mutation} =
             Audit.record_mutation(mutation_attrs(%{tenant_id: 41, auditable_id: "owned"}))

    assert {:ok, _other_mutation} =
             Audit.record_mutation(mutation_attrs(%{tenant_id: 42, auditable_id: "other"}))

    assert {:ok, _null_mutation} =
             Audit.record_mutation(mutation_attrs(%{tenant_id: nil, auditable_id: "null"}))

    assert {:ok, owned_action} =
             Audit.record_action(action_attrs(%{tenant_id: 41, event: "owned.event"}))

    assert {:ok, _other_action} =
             Audit.record_action(action_attrs(%{tenant_id: 42, event: "other.event"}))

    assert {:ok, _null_action} =
             Audit.record_action(action_attrs(%{tenant_id: nil, event: "null.event"}))

    assert {:ok, [%Mutation{id: mutation_id}]} = Audit.list_mutations(owner)
    assert mutation_id == owned_mutation.id

    assert {:ok, [%Action{id: action_id}]} = Audit.list_actions(owner)
    assert action_id == owned_action.id
  end

  test "rejects unknown actor_type and missing required fields" do
    assert {:error, unknown_actor} =
             Audit.record_mutation(%{
               actor_type: "system",
               actor_id: 42,
               auditable_type: "App\\Core\\Company\\Models\\Company",
               auditable_id: "73",
               event: "created",
               occurred_at: ~N[2026-08-13 03:00:00]
             })

    assert %{actor_type: ["is invalid"]} = errors_on(unknown_actor)

    assert {:error, missing} = Audit.record_mutation(%{})

    assert %{
             actor_type: ["can't be blank"],
             actor_id: ["can't be blank"],
             auditable_type: ["can't be blank"],
             auditable_id: ["can't be blank"],
             event: ["can't be blank"],
             occurred_at: ["can't be blank"]
           } = errors_on(missing)
  end

  defp mutation_attrs(overrides) do
    Map.merge(
      %{
        actor_type: "user",
        actor_id: 42,
        auditable_type: "App\\Core\\Company\\Models\\Company",
        auditable_id: "73",
        event: "created",
        occurred_at: ~N[2026-08-13 03:00:00]
      },
      overrides
    )
  end

  defp action_attrs(overrides) do
    Map.merge(
      %{
        actor_type: "user",
        actor_id: 42,
        event: "http.request",
        occurred_at: ~N[2026-08-13 03:00:00]
      },
      overrides
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
