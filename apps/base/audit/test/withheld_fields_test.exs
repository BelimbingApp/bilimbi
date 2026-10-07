defmodule Bilimbi.Base.Audit.WithheldFieldsTest do
  @moduledoc """
  The owning module's field policy governs every audit read: the values of a
  withheld field are taken out of each mutation the API returns, and the
  field is still named so the reader knows the record changed.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Mutation
  alias Bilimbi.Base.Audit.TestAuthorization
  alias Bilimbi.Base.Audit.Web.MutationDiff
  alias Bilimbi.Base.Tenancy

  import Bilimbi.Base.Audit.TestFixtures
  import Bilimbi.Base.Tenancy.TestFixtures

  @type_name "Bilimbi.Core.Company.Schema"

  setup do
    create_tenants_table!()
    create_audit_tables!()
    insert_tenant!(%{id: 41})
    {:ok, scope} = Tenancy.scope(41)

    previous = Application.get_env(:bilimbi_base_audit, :authorization)
    Application.put_env(:bilimbi_base_audit, :authorization, TestAuthorization)

    on_exit(fn ->
      Application.put_env(:bilimbi_base_audit, :authorization, previous)
    end)

    {:ok, scope: scope}
  end

  describe "a reader without the field's capability" do
    setup %{scope: scope} do
      TestAuthorization.withhold!(%{@type_name => ["tax_id", "email"]})

      {:ok, updated} =
        record!(scope, %{
          event: "updated",
          old_values: %{"tax_id" => "TAX-OLD", "email" => "old@example.com", "name" => "A"},
          new_values: %{"tax_id" => "TAX-NEW", "email" => "new@example.com", "name" => "B"}
        })

      {:ok, created} =
        record!(scope, %{
          auditable_id: "74",
          event: "created",
          new_values: %{"tax_id" => "TAX-74", "name" => "C"}
        })

      {:ok, other_type} =
        record!(scope, %{
          auditable_type: "Example.Other",
          auditable_id: "75",
          event: "created",
          new_values: %{"tax_id" => "OTHER-TAX"}
        })

      {:ok, updated: updated, created: created, other_type: other_type}
    end

    test "list_mutations/2 returns no value of a withheld field, and names the field", %{
      scope: scope,
      updated: updated
    } do
      page = Audit.list_mutations(scope, page_size: 50)

      entry = Enum.find(page.entries, &(&1.id == updated.id))
      assert entry.withheld == ["tax_id", "email"]
      assert entry.old_values == %{"name" => "A"}
      assert entry.new_values == %{"name" => "B"}
      refute inspect(page) =~ "TAX-OLD"
      refute inspect(page) =~ "TAX-NEW"
      refute inspect(page) =~ "TAX-74"
      refute inspect(page) =~ "old@example.com"
    end

    test "every other read of mutations is governed the same way", %{scope: scope} do
      {:ok, all} = Audit.list_mutations(scope)
      {:ok, recent} = Audit.list_recent_mutations(scope, 10)

      {:ok, subject} =
        Audit.list_subject_mutations(scope, [@type_name], 73)

      for entries <- [all, recent, subject] do
        refute inspect(entries) =~ "TAX-OLD"
        refute inspect(entries) =~ "old@example.com"
      end

      assert [%Mutation{withheld: ["tax_id", "email"]}] = subject
    end

    test "a create lists the field as withheld and a type with no policy is untouched", %{
      scope: scope,
      created: created,
      other_type: other_type
    } do
      {:ok, all} = Audit.list_mutations(scope)

      created = Enum.find(all, &(&1.id == created.id))
      assert created.withheld == ["tax_id"]
      assert created.new_values == %{"name" => "C"}

      other = Enum.find(all, &(&1.id == other_type.id))
      assert other.withheld == []
      assert other.new_values == %{"tax_id" => "OTHER-TAX"}
    end

    test "the diff rows carry the field as withheld, with no values, in field order", %{
      scope: scope,
      updated: updated
    } do
      {:ok, all} = Audit.list_mutations(scope)
      entry = Enum.find(all, &(&1.id == updated.id))

      assert MutationDiff.changed_fields(entry) == ["email", "name", "tax_id"]

      assert [
               %{field: "email", withheld: true, old: :absent, new: :absent},
               %{field: "name", withheld: false, old: {:text, "A"}, new: {:text, "B"}},
               %{field: "tax_id", withheld: true, old: :absent, new: :absent}
             ] = MutationDiff.rows(entry)
    end

    test "a field the change left alone is not claimed as changed", %{scope: scope} do
      {:ok, _} =
        record!(scope, %{
          auditable_id: "76",
          event: "updated",
          old_values: %{"tax_id" => "SAME", "name" => "A"},
          new_values: %{"tax_id" => "SAME", "name" => "B"}
        })

      {:ok, subject} = Audit.list_subject_mutations(scope, [@type_name], 76)

      assert [%Mutation{withheld: [], old_values: %{"name" => "A"}}] = subject
    end
  end

  test "a reader who holds the capability sees every recorded value", %{scope: scope} do
    TestAuthorization.withhold!(%{})

    {:ok, updated} =
      record!(scope, %{
        event: "updated",
        old_values: %{"tax_id" => "TAX-OLD"},
        new_values: %{"tax_id" => "TAX-NEW"}
      })

    {:ok, subject} = Audit.list_subject_mutations(scope, [@type_name], 73)

    assert [%Mutation{id: id, withheld: [], old_values: %{"tax_id" => "TAX-OLD"}}] = subject
    assert id == updated.id

    assert [%{field: "tax_id", withheld: false, new: {:text, "TAX-NEW"}}] =
             MutationDiff.rows(hd(subject))
  end

  test "without an answer from Authz nothing is declared and values read as recorded", %{
    scope: scope
  } do
    Application.put_env(:bilimbi_base_audit, :authorization, nil)

    {:ok, _} =
      record!(scope, %{event: "created", new_values: %{"tax_id" => "TAX-1"}})

    assert {:ok, [%Mutation{withheld: [], new_values: %{"tax_id" => "TAX-1"}}]} =
             Audit.list_subject_mutations(scope, [@type_name], 73)
  end

  defp record!(scope, overrides) do
    Audit.record_mutation(
      scope,
      Map.merge(
        %{
          actor_type: "user",
          actor_id: 42,
          auditable_type: @type_name,
          auditable_id: "73",
          event: "created",
          occurred_at: ~N[2026-08-13 03:00:00]
        },
        overrides
      )
    )
  end
end
