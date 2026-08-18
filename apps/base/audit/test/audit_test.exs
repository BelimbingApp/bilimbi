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

  test "records a mutation with jsonb payloads, inet, and an unscoped tenant" do
    assert {:ok, %Mutation{} = mutation} =
             Audit.record_mutation(
               :unscoped,
               %{
                 company_id: 73,
                 tenant_id: 99,
                 actor_type: "user",
                 actor_id: 42,
                 auditable_type: "App\\Core\\Company\\Models\\Company",
                 auditable_id: "73",
                 event: "updated",
                 occurred_at: ~N[2026-08-13 03:00:00],
                 old_values: %{"name" => "Old"},
                 new_values: %{"name" => "New"},
                 ip_address: "192.0.2.10"
               }
             )

    refute Map.has_key?(mutation, :__meta__)
    assert mutation.tenant_id == nil
    assert mutation.company_id == 73
    assert mutation.old_values == %{"name" => "Old"}
    assert mutation.new_values == %{"name" => "New"}
    assert mutation.ip_address.address == {192, 0, 2, 10}
    assert mutation.source == "listener"
  end

  test "records an action with jsonb payload, inet, and an unscoped tenant" do
    assert {:ok, %Action{} = action} =
             Audit.record_action(
               :unscoped,
               %{
                 company_id: 73,
                 tenant_id: 99,
                 actor_type: "console",
                 actor_id: 0,
                 event: "console.command",
                 occurred_at: ~N[2026-08-13 03:01:00],
                 payload: %{"command" => "mix test"},
                 ip_address: "192.0.2.11",
                 is_retained: true
               }
             )

    refute Map.has_key?(action, :__meta__)
    assert action.tenant_id == nil
    assert action.payload == %{"command" => "mix test"}
    assert action.ip_address.address == {192, 0, 2, 11}
    assert action.is_retained
  end

  test "records guest actor facts through the public API" do
    assert {:ok, %Mutation{actor_type: "guest", actor_id: 0, tenant_id: nil}} =
             Audit.record_mutation(:unscoped, mutation_attrs(%{actor_type: "guest", actor_id: 0}))

    assert {:ok, %Action{actor_type: "guest", actor_id: 0, tenant_id: nil}} =
             Audit.record_action(:unscoped, action_attrs(%{actor_type: "guest", actor_id: 0}))
  end

  test "scoped recording derives tenant_id from the scope and ignores a spoofed attribute" do
    insert_tenant!(%{id: 41})
    insert_tenant!(%{id: 42, is_platform_operator: false})

    {:ok, owner} = Tenancy.scope(41)

    assert {:ok, %Mutation{tenant_id: 41}} =
             Audit.record_mutation(owner, mutation_attrs(%{tenant_id: 42, auditable_id: "owned"}))

    assert {:ok, %Action{tenant_id: 41}} =
             Audit.record_action(owner, action_attrs(%{tenant_id: 42, event: "owned.event"}))
  end

  test "lists mutations and actions for the scope and excludes other tenants and null-tenant rows" do
    insert_tenant!(%{id: 41})
    insert_tenant!(%{id: 42, is_platform_operator: false})

    {:ok, owner} = Tenancy.scope(41)
    {:ok, other} = Tenancy.scope(42)

    assert {:ok, owned_mutation} =
             Audit.record_mutation(owner, mutation_attrs(%{auditable_id: "owned"}))

    assert {:ok, _other_mutation} =
             Audit.record_mutation(other, mutation_attrs(%{auditable_id: "other"}))

    assert {:ok, _null_mutation} =
             Audit.record_mutation(:unscoped, mutation_attrs(%{auditable_id: "null"}))

    assert {:ok, owned_action} =
             Audit.record_action(owner, action_attrs(%{event: "owned.event"}))

    assert {:ok, _other_action} =
             Audit.record_action(other, action_attrs(%{event: "other.event"}))

    assert {:ok, _null_action} =
             Audit.record_action(:unscoped, action_attrs(%{event: "null.event"}))

    assert {:ok, [%Mutation{id: mutation_id}]} = Audit.list_mutations(owner)
    assert mutation_id == owned_mutation.id

    assert {:ok, [%Action{id: action_id}]} = Audit.list_actions(owner)
    assert action_id == owned_action.id
  end

  test "rejects unknown actor_type, missing required fields, and explicit nil defaults" do
    assert {:error, unknown_actor} =
             Audit.record_mutation(:unscoped, mutation_attrs(%{actor_type: "system"}))

    assert %{actor_type: ["is invalid"]} = errors_on(unknown_actor)

    assert {:error, missing} = Audit.record_mutation(:unscoped, %{})

    assert %{
             actor_type: ["can't be blank"],
             actor_id: ["can't be blank"],
             auditable_type: ["can't be blank"],
             auditable_id: ["can't be blank"],
             event: ["can't be blank"],
             occurred_at: ["can't be blank"]
           } = errors_on(missing)

    assert {:error, nil_source} =
             Audit.record_mutation(:unscoped, mutation_attrs(%{source: nil}))

    assert %{source: ["can't be blank"]} = errors_on(nil_source)

    assert {:error, nil_retained} =
             Audit.record_action(:unscoped, action_attrs(%{is_retained: nil}))

    assert %{is_retained: ["can't be blank"]} = errors_on(nil_retained)
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

  test "paginates and searches mutations by subject, event, and trace" do
    insert_tenant!(%{id: 41})
    {:ok, scope} = Tenancy.scope(41)

    for i <- 1..30 do
      Audit.record_mutation(
        scope,
        mutation_attrs(%{
          auditable_id: to_string(i),
          subject_name: if(rem(i, 2) == 0, do: "Widget #{i}", else: "Gadget #{i}"),
          event: if(rem(i, 3) == 0, do: "created", else: "updated"),
          trace_id: "trc#{i}",
          occurred_at: NaiveDateTime.add(~N[2026-08-13 03:00:00], i, :second)
        })
      )
    end

    page1 =
      Audit.list_mutations(scope, page: 1, page_size: 10, sort_by: :occurred_at, sort_dir: :desc)

    assert page1.total_entries == 30
    assert page1.total_pages == 3
    assert length(page1.entries) == 10
    assert hd(page1.entries).auditable_id == "30"

    # Filter by event
    created_page = Audit.list_mutations(scope, event: "created", page_size: 50)
    assert created_page.total_entries == 10
    assert Enum.all?(created_page.entries, &(&1.event == "created"))

    # Search by subject_name
    search_page = Audit.list_mutations(scope, search: "Widget 1", page_size: 50)
    assert search_page.total_entries >= 1
    assert Enum.all?(search_page.entries, &String.contains?(&1.subject_name || "", "Widget 1"))
  end

  test "paginates, searches, and filters actions by actor_type, event_family, result, and diagnostics" do
    insert_tenant!(%{id: 41})
    {:ok, scope} = Tenancy.scope(41)

    {:ok, http_action} =
      Audit.record_action(
        scope,
        action_attrs(%{
          event: "http.request",
          actor_type: "user",
          payload: %{"method" => "GET", "status" => 200, "route" => "admin.users"},
          url: "https://example.test/admin/users",
          is_retained: false
        })
      )

    {:ok, failed_http} =
      Audit.record_action(
        scope,
        action_attrs(%{
          event: "http.request",
          actor_type: "user",
          payload: %{"method" => "POST", "status" => 500, "route" => "admin.users.create"},
          url: "https://example.test/admin/users/create",
          is_retained: true
        })
      )

    {:ok, auth_action} =
      Audit.record_action(
        scope,
        action_attrs(%{
          event: "auth.login.failed",
          actor_type: "guest",
          payload: %{"email" => "bad@example.test"}
        })
      )

    # All actions
    all_page = Audit.list_actions(scope, diagnostics: "show", page_size: 10)
    assert all_page.total_entries == 3

    # Filter by family
    http_page = Audit.list_actions(scope, event_family: "http", diagnostics: "show")
    assert http_page.total_entries == 2

    # Filter by actor_type
    guest_page = Audit.list_actions(scope, actor_type: "guest", diagnostics: "show")
    assert guest_page.total_entries == 1
    assert hd(guest_page.entries).id == auth_action.id

    # Filter by result = failure
    failed_page = Audit.list_actions(scope, result: "failure", diagnostics: "show")
    assert failed_page.total_entries == 2

    # Filter by result = retained
    retained_page = Audit.list_actions(scope, result: "retained", diagnostics: "show")
    assert retained_page.total_entries == 1
    assert hd(retained_page.entries).id == failed_http.id

    # Toggle retention
    assert {:ok, updated} = Audit.toggle_retained(scope, http_action.id)
    assert updated.is_retained == true
    assert {:ok, toggled_back} = Audit.toggle_retained(scope, http_action.id)
    assert toggled_back.is_retained == false

    # Toggle retention on unknown id
    assert {:error, :not_found} = Audit.toggle_retained(scope, 999_999)
  end

  test "safely escapes wildcard characters in search" do
    insert_tenant!(%{id: 41})
    {:ok, scope} = Tenancy.scope(41)

    {:ok, _normal} =
      Audit.record_mutation(
        scope,
        mutation_attrs(%{subject_name: "Widget", auditable_id: "w1"})
      )

    {:ok, _percent} =
      Audit.record_mutation(
        scope,
        mutation_attrs(%{subject_name: "100% discount", auditable_id: "w2"})
      )

    {:ok, _underscore} =
      Audit.record_mutation(
        scope,
        mutation_attrs(%{subject_name: "user_name", auditable_id: "w3"})
      )

    # Searching "%" matches only the literal "%" row, not all rows
    percent_page = Audit.list_mutations(scope, search: "%")
    assert percent_page.total_entries == 1
    assert hd(percent_page.entries).subject_name == "100% discount"

    # Searching "_" matches only the literal "_" row, not single-character wildcards
    underscore_page = Audit.list_mutations(scope, search: "_")
    assert underscore_page.total_entries == 1
    assert hd(underscore_page.entries).subject_name == "user_name"
  end
end
