defmodule Bilimbi.Core.Company.RelationshipRolesTest do
  use Bilimbi.Base.Database.DataCase, async: true
  alias Bilimbi.Base.{Repo, Tenancy}
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.RelationshipCatalogue
  alias Bilimbi.Core.Company.Relationships
  import Bilimbi.Core.Company.TestFixtures
  import Bilimbi.Base.Database.TestHelpers, only: [errors_on: 1]

  setup do
    create_company_identity_tables!()
    create_external_access_tables!()
    insert_tenant!()
    insert_tenant!(%{id: 42, is_platform_operator: false})
    insert_company!()
    insert_company!(%{id: 74, code: "supplier", name: "Supplier"})
    insert_company!(%{id: 75, code: "foreign", tenant_id: 42})
    :ok = RelationshipCatalogue.ensure_defaults(Repo)
    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  test "default roles coexist and have explicit inverse semantics without portal grants", %{
    scope: scope
  } do
    {:ok, roles} = Company.list_relationship_types()
    vendor = Enum.find(roles, &(&1.code == "vendor"))
    customer = Enum.find(roles, &(&1.code == "customer"))

    assert {:ok, v} =
             Company.create_relationship(scope, 73, %{
               related_company_id: 74,
               relationship_type_id: vendor.id
             })

    assert {:ok, c} =
             Company.create_relationship(scope, 73, %{
               related_company_id: 74,
               relationship_type_id: customer.id
             })

    refute v.id == c.id
    assert {:ok, outgoing} = Company.list_relationships(scope, 73)

    assert MapSet.new(Enum.map(outgoing, & &1.role_label)) ==
             MapSet.new(["Vendor / Supplier", "Customer"])

    assert {:ok, incoming} = Company.list_relationships(scope, 74)
    assert Enum.find(incoming, &(&1.id == v.id)).role_label == "Customer"
    assert Enum.find(incoming, &(&1.id == c.id)).role_label == "Vendor / Supplier"
    assert Repo.aggregate(Bilimbi.Core.Company.ExternalAccess, :count) == 0
  end

  test "a prospect becomes a customer by ending one dated link and starting the other", %{
    scope: scope
  } do
    {:ok, roles} = Company.list_relationship_types()
    prospect = Enum.find(roles, &(&1.code == "prospect"))
    customer = Enum.find(roles, &(&1.code == "customer"))

    assert {:ok, first} =
             Company.create_relationship(scope, 73, %{
               related_company_id: 74,
               relationship_type_id: prospect.id,
               effective_from: "2026-01-01"
             })

    assert {:ok, ended} =
             Company.end_relationship(scope, 73, first.id, %{"effective_to" => "2026-03-31"})

    assert ended.id == first.id and ended.deleted_at == nil

    assert {:ok, second} =
             Company.create_relationship(scope, 73, %{
               related_company_id: 74,
               relationship_type_id: customer.id,
               effective_from: "2026-04-01"
             })

    assert {:ok, rows} = Company.list_relationships(scope, 73)

    assert [{"Prospect", ~D[2026-01-01], ~D[2026-03-31]}, {"Customer", ~D[2026-04-01], nil}] ==
             rows
             |> Enum.sort_by(& &1.id)
             |> Enum.map(&{&1.role_label, &1.effective_from, &1.effective_to})

    assert [first.id, second.id] == rows |> Enum.map(& &1.id) |> Enum.sort()
  end

  test "ending defaults to today, keeps the link, and is separate from unlinking", %{
    scope: scope
  } do
    {:ok, roles} = Company.list_relationship_types()
    vendor = Enum.find(roles, &(&1.code == "vendor"))

    {:ok, rel} =
      Company.create_relationship(scope, 73, %{
        related_company_id: 74,
        relationship_type_id: vendor.id,
        effective_from: "2026-01-01"
      })

    assert {:ok, %{effective_to: today}} = Company.end_relationship(scope, 73, rel.id)
    assert today == Date.utc_today()

    assert {:ok, [%{effective_to: ^today, unlinked_at: nil}]} =
             Company.list_relationships(scope, 73)

    assert {:error, %Ecto.Changeset{} = cs} =
             Company.end_relationship(scope, 73, rel.id, %{"effective_to" => "2025-12-31"})

    assert %{effective_to: [_]} = errors_on(cs)
    assert :ok = Company.delete_relationship(scope, 73, rel.id)
    assert {:ok, []} = Company.list_relationships(scope, 73)

    assert {:ok, [%{effective_to: ^today}]} =
             Company.list_relationships(scope, 73, include_unlinked: true)
  end

  test "forged source and cross-tenant targets cannot change relationship ownership", %{
    scope: scope
  } do
    {:ok, [role | _]} = Company.list_relationship_types()

    assert {:error, :company_not_found} =
             Company.create_relationship(scope, 73, %{
               related_company_id: 75,
               relationship_type_id: role.id
             })

    assert {:ok, rel} =
             Company.create_relationship(scope, 73, %{
               company_id: 75,
               related_company_id: 74,
               relationship_type_id: role.id
             })

    assert rel.company_id == 73
  end

  test "reference seeding preserves operator rename and retirement", %{scope: scope} do
    {:ok, roles} = Company.list_relationship_types()
    role = Enum.find(roles, &(&1.code == "vendor"))
    Repo.update!(Ecto.Changeset.change(role, name: "Preferred supplier", is_active: false))
    assert :ok = RelationshipCatalogue.ensure_defaults(Repo)

    assert {:ok, %{name: "Preferred supplier", is_active: false}} =
             Company.get_relationship_type(role.id)

    assert {:error, %Ecto.Changeset{}} =
             Company.create_relationship(scope, 73, %{
               related_company_id: 74,
               relationship_type_id: role.id
             })
  end

  describe "live relationship uniqueness" do
    @overlap "is already assigned between these companies for an overlapping period"

    setup do
      {:ok, roles} = Company.list_relationship_types()
      %{vendor: Enum.find(roles, &(&1.code == "vendor"))}
    end

    defp attrs(vendor, extra \\ %{}),
      do: Map.merge(%{related_company_id: 74, relationship_type_id: vendor.id}, extra)

    test "an exact replay is idempotent; any overlapping period is refused", %{
      scope: scope,
      vendor: vendor
    } do
      assert {:ok, first} = Company.create_relationship(scope, 73, attrs(vendor))
      assert {:ok, replay} = Company.create_relationship(scope, 73, attrs(vendor))
      assert replay.id == first.id

      assert {:error, %Ecto.Changeset{} = changeset} =
               Company.create_relationship(
                 scope,
                 73,
                 attrs(vendor, %{effective_from: ~D[2026-10-14]})
               )

      assert %{relationship_type_id: [@overlap]} = errors_on(changeset)
      assert {:ok, [_only_one]} = Company.list_relationships(scope, 73)
    end

    test "a replay with a future end date is idempotent, and overlapping ranges are refused", %{
      scope: scope,
      vendor: vendor
    } do
      dated = attrs(vendor, %{effective_from: ~D[2026-01-01], effective_to: ~D[2030-12-31]})
      assert {:ok, first} = Company.create_relationship(scope, 73, dated)
      assert {:ok, replay} = Company.create_relationship(scope, 73, dated)
      assert replay.id == first.id

      for {from, to} <- [
            {~D[2026-06-01], ~D[2027-06-01]},
            {~D[2025-01-01], ~D[2026-01-01]},
            {~D[2030-12-31], nil},
            {nil, nil}
          ] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Company.create_relationship(
                   scope,
                   73,
                   attrs(vendor, %{effective_from: from, effective_to: to})
                 )

        assert %{relationship_type_id: [@overlap]} = errors_on(changeset)
      end

      assert {:ok, adjacent} =
               Company.create_relationship(
                 scope,
                 73,
                 attrs(vendor, %{effective_from: ~D[2031-01-01]})
               )

      assert adjacent.id != first.id

      assert {:error, %Ecto.Changeset{} = changeset} =
               Company.update_relationship(scope, 73, adjacent.id, %{effective_from: "2030-06-01"})

      assert %{effective_to: [@overlap]} = errors_on(changeset)
      assert {:ok, [_, _]} = Company.list_relationships(scope, 73)
    end

    test "unlinked links do not block, and other roles or targets are independent", %{
      scope: scope,
      vendor: vendor
    } do
      assert {:ok, first} = Company.create_relationship(scope, 73, attrs(vendor))
      assert :ok = Company.delete_relationship(scope, 73, first.id)
      assert {:ok, second} = Company.create_relationship(scope, 73, attrs(vendor))
      assert second.id != first.id
    end

    test "preview agrees with commit: a replay passes, an overlap is refused", %{
      scope: scope,
      vendor: vendor
    } do
      input = %{"related_company_id" => 74, "relationship_type_id" => vendor.id}
      assert {:ok, _} = Relationships.preview(scope, 73, nil, "create", input)
      assert {:ok, _} = Company.create_relationship(scope, 73, attrs(vendor))
      assert {:ok, _} = Relationships.preview(scope, 73, nil, "create", input)

      assert {:error, %Ecto.Changeset{}} =
               Relationships.preview(
                 scope,
                 73,
                 nil,
                 "create",
                 Map.put(input, "effective_from", "2026-10-14")
               )
    end

    test "ended and unlinked links stay history and allow a later link", %{
      scope: scope,
      vendor: vendor
    } do
      assert {:ok, ended} =
               Company.create_relationship(
                 scope,
                 73,
                 attrs(vendor, %{effective_from: ~D[2025-01-01], effective_to: ~D[2025-12-31]})
               )

      later = attrs(vendor, %{effective_from: ~D[2026-01-01]})
      assert {:ok, current} = Company.create_relationship(scope, 73, later)
      assert :ok = Company.delete_relationship(scope, 73, current.id)
      assert {:ok, again} = Company.create_relationship(scope, 73, later)

      assert {:ok, rows} = Company.list_relationships(scope, 73, include_unlinked: true)
      assert MapSet.new(Enum.map(rows, & &1.id)) == MapSet.new([ended.id, current.id, again.id])
    end

    test "reopening an ended link cannot duplicate the open one", %{scope: scope, vendor: vendor} do
      assert {:ok, ended} =
               Company.create_relationship(
                 scope,
                 73,
                 attrs(vendor, %{effective_from: ~D[2025-01-01], effective_to: ~D[2025-12-31]})
               )

      assert {:ok, _open} =
               Company.create_relationship(
                 scope,
                 73,
                 attrs(vendor, %{effective_from: ~D[2026-01-01]})
               )

      assert {:error, %Ecto.Changeset{} = changeset} =
               Company.update_relationship(scope, 73, ended.id, %{effective_to: nil})

      assert %{effective_to: [@overlap]} = errors_on(changeset)
    end

    test "preview of reopening an ended link refuses what commit would refuse", %{
      scope: scope,
      vendor: vendor
    } do
      assert {:ok, ended} =
               Company.create_relationship(
                 scope,
                 73,
                 attrs(vendor, %{effective_from: ~D[2025-01-01], effective_to: ~D[2025-12-31]})
               )

      assert {:ok, open} =
               Company.create_relationship(
                 scope,
                 73,
                 attrs(vendor, %{effective_from: ~D[2026-01-01]})
               )

      clear = %{"effective_to" => nil}

      assert {:error, %Ecto.Changeset{}} =
               Relationships.preview(scope, 73, ended.id, "update", clear)

      assert {:ok, _} = Relationships.preview(scope, 73, open.id, "update", clear)
    end

    test "the same role in the opposite direction is a different link", %{
      scope: scope,
      vendor: vendor
    } do
      assert {:ok, _} = Company.create_relationship(scope, 73, attrs(vendor))

      assert {:ok, _} =
               Company.create_relationship(scope, 74, %{
                 related_company_id: 73,
                 relationship_type_id: vendor.id
               })
    end
  end
end
