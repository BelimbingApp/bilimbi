defmodule Bilimbi.Core.UserAdministrationTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User, as: CoreUser
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Bilimbi.Core.UserAdministration
  alias Bilimbi.Core.UserAdministration.Entry
  alias Bilimbi.Core.UserAdministration.Options
  alias Bilimbi.Core.UserAdministration.Page
  alias Bilimbi.Core.UserAdministration.Role
  alias Bilimbi.Core.UserAdministration.TestAuthz
  alias Ecto.Adapters.SQL

  import Bilimbi.Base.Authz.TestFixtures, only: [create_authz_tables!: 0]

  import Bilimbi.Core.Company.TestFixtures,
    only: [insert_company!: 1, insert_tenant!: 1]

  setup do
    UserFixtures.create_user_tables!()
    create_authz_tables!()
    TestAuthz.install_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    insert_tenant!(%{id: 1, name: "Tenant one", is_platform_operator: false})
    insert_tenant!(%{id: 2, name: "Tenant two", is_platform_operator: false})
    insert_company!(%{id: 10, tenant_id: 1, name: "Alpha Company", code: "alpha"})
    insert_company!(%{id: 11, tenant_id: 1, name: "Archive Company", code: "archive"})
    insert_company!(%{id: 12, tenant_id: 1, name: "Live Company", code: "live"})
    insert_company!(%{id: 20, tenant_id: 2, name: "Other Company", code: "other"})

    :ok
  end

  test "returns one schema-free page with archived affiliations and bounded roles" do
    user!(1, 10, "Ada", "ada@example.com", ~N[2026-01-01 00:00:00])
    user!(2, 11, "Grace", "grace@example.com", ~N[2026-01-02 00:00:00])
    archive_company!(11)

    assert {:ok, role} =
             Authz.create_role(scope(), 10, %{name: "Viewer", code: "viewer"})

    assert {:ok, :assigned} = Authz.assign_role(scope(), 10, :user, 1, role.id)

    assert %Page{
             entries: [
               %Entry{id: 1, company_archived: false, roles: [listed_role]},
               %Entry{id: 2, company_archived: true, roles: []}
             ],
             page: 1,
             page_size: 25,
             total_entries: 2,
             total_pages: 1
           } = page = UserAdministration.list_users(scope())

    assert listed_role.id == role.id
    [entry | _entries] = page.entries

    assert Map.keys(Map.from_struct(page)) |> Enum.sort() ==
             [:entries, :page, :page_size, :total_entries, :total_pages]

    assert Map.keys(Map.from_struct(entry)) |> Enum.sort() ==
             [
               :company_archived,
               :company_id,
               :company_name,
               :created_at,
               :email,
               :id,
               :name,
               :roles
             ]

    assert Map.keys(Map.from_struct(listed_role)) |> Enum.sort() ==
             [:code, :id, :is_system, :name]

    refute Ecto.Queryable.impl_for(page)
    refute Ecto.Queryable.impl_for(entry)
    refute Ecto.Queryable.impl_for(listed_role)
  end

  test "excludes null and cross-tenant affiliations while preserving archived names" do
    user!(1, 10, "Visible", "visible@example.com", nil)
    user!(2, 11, "Archived", "archived@example.com", nil)
    user!(3, nil, "Unassigned", "unassigned@example.com", nil)
    user!(4, 20, "Foreign", "foreign@example.com", nil)
    archive_company!(11)

    assert %Page{entries: entries, total_entries: 2} =
             UserAdministration.list_users(scope(), sort_by: :name)

    assert Enum.map(entries, &{&1.id, &1.company_name, &1.company_archived}) == [
             {2, "Archive Company", true},
             {1, "Alpha Company", false}
           ]
  end

  test "uses PostgreSQL LIKE case and wildcard behavior and preserves PHP-falsey filters" do
    user!(1, 10, "ALPHA", "one@example.com", nil)
    user!(2, 10, "Alpha", "two@example.com", nil)
    user!(3, 10, "Alpine", "target@EXAMPLE.com", nil)

    assert ids(search: "ALPHA") == [1]
    assert ids(search: "LPH") == [1]
    assert ids(search: "target@") == [3]
    assert ids(search: "A_pha") == [2]
    assert ids(search: "Al%") == [2, 3]
    assert ids(search: "%@EXAMPLE.com") == [3]
    assert MapSet.new(ids(search: "")) == MapSet.new([1, 2, 3])
    assert MapSet.new(ids(search: "0")) == MapSet.new([1, 2, 3])
  end

  test "supports every sort direction with a durable descending id tie-breaker" do
    user!(1, 10, "Same", "z@example.com", ~N[2026-01-02 00:00:00])
    user!(2, 10, "Same", "a@example.com", ~N[2026-01-01 00:00:00])
    user!(3, 11, "Other", "m@example.com", nil)

    assert ids(sort_by: :name, sort_dir: :asc) == [3, 2, 1]
    assert ids(sort_by: :name, sort_dir: :desc) == [2, 1, 3]
    assert ids(sort_by: :email, sort_dir: :asc) == [2, 3, 1]
    assert ids(sort_by: :email, sort_dir: :desc) == [1, 3, 2]
    assert ids(sort_by: :company_name, sort_dir: :asc) == [2, 1, 3]
    assert ids(sort_by: :company_name, sort_dir: :desc) == [3, 2, 1]
    assert ids(sort_by: :created_at, sort_dir: :asc) == [2, 1, 3]
    assert ids(sort_by: :created_at, sort_dir: :desc) == [3, 1, 2]
  end

  test "filters with OR role semantics before count and pagination and deduplicates summaries" do
    Enum.each(1..27, fn id ->
      user!(
        id,
        10,
        "User #{String.pad_leading(Integer.to_string(id), 2, "0")}",
        "u#{id}@example.com",
        nil
      )
    end)

    assert {:ok, first} = custom_role!(10, "First", "first")
    assert {:ok, second} = custom_role!(10, "Second", "second")

    Enum.each(1..15, fn id ->
      assert {:ok, :assigned} = Authz.assign_role(scope(), 10, :user, id, first.id)
    end)

    Enum.each(15..27, fn id ->
      assert {:ok, :assigned} = Authz.assign_role(scope(), 10, :user, id, second.id)
    end)

    assert %Page{entries: entries, total_entries: 27, total_pages: 2} =
             UserAdministration.list_users(scope(),
               role_ids: [first.id, second.id],
               page_size: 25
             )

    assert length(entries) == 25

    assert %Entry{roles: [%Role{id: first_id}, %Role{id: second_id}]} =
             Enum.find(entries, &(&1.id == 15))

    assert [first_id, second_id] == [first.id, second.id]

    assert %Page{entries: [], total_entries: 0, total_pages: 0} =
             UserAdministration.list_users(scope(), role_ids: [9_999_999])
  end

  test "shows only integration-valid system and custom roles" do
    user!(1, 10, "Ada", "ada@example.com", nil)

    assert {:ok, live_custom} = custom_role!(10, "Live custom", "live_custom")
    assert {:ok, archived_custom} = custom_role!(11, "Archived custom", "archived_custom")
    assert {:ok, foreign_custom} = custom_role!(11, "Foreign custom", "foreign_custom")
    assert {:ok, missing_custom} = custom_role!(10, "Missing custom", "missing_custom")
    assert {:ok, owned_system} = custom_role!(10, "Owned system", "owned_system")
    assert {:ok, global_custom} = custom_role!(10, "Global custom", "global_custom")

    for role <- [
          live_custom,
          archived_custom,
          foreign_custom,
          missing_custom,
          owned_system,
          global_custom
        ] do
      assert {:ok, :assigned} = Authz.assign_role(scope(), 10, :user, 1, role.id)
    end

    assert {:ok, _} = Authz.reconcile_system_roles()
    system_role = Enum.find(Authz.list_roles(scope()), & &1.is_system)
    assert {:ok, :assigned} = Authz.assign_role(scope(), 10, :user, 1, system_role.id)
    assert {:ok, :assigned} = Authz.assign_role(scope(), 12, :user, 1, system_role.id)

    archive_company!(11)
    move_role_to_missing_company!(foreign_custom.id, 20)
    make_assignment_role_missing!(missing_custom.id)
    corrupt_role_identity!(owned_system.id, 10, true)
    corrupt_role_identity!(global_custom.id, nil, false)

    assert %Page{entries: [%Entry{roles: roles}]} = UserAdministration.list_users(scope())

    assert Enum.map(roles, & &1.id) ==
             [live_custom.id, system_role.id]
             |> Enum.sort_by(fn id -> Enum.find(roles, &(&1.id == id)).name end)

    assert ids(role_ids: [archived_custom.id]) == []
    assert ids(role_ids: [foreign_custom.id]) == []
    assert ids(role_ids: [missing_custom.id]) == []
    assert ids(role_ids: [owned_system.id]) == []
    assert ids(role_ids: [global_custom.id]) == []
    assert ids(role_ids: [system_role.id]) == [1]
  end

  test "orders unique role summaries by name, code, and durable id" do
    user!(1, 10, "Ada", "ada@example.com", nil)
    assert {:ok, same_b} = custom_role!(10, "Same", "b")
    assert {:ok, same_a_one} = custom_role!(10, "Same", "a")
    assert {:ok, same_a_two} = custom_role!(12, "Same", "a")

    for role <- [same_b, same_a_one, same_a_two] do
      assert {:ok, :assigned} = Authz.assign_role(scope(), 10, :user, 1, role.id)
    end

    assert %Page{entries: [%Entry{roles: roles}]} = UserAdministration.list_users(scope())

    same_a_ids = Enum.sort([same_a_one.id, same_a_two.id])
    assert Enum.map(roles, & &1.id) == same_a_ids ++ [same_b.id]
  end

  test "returns truthful empty and out-of-range envelopes" do
    assert %Page{entries: [], page: 1, total_entries: 0, total_pages: 0} =
             UserAdministration.list_users(scope())

    Enum.each(1..26, fn id ->
      user!(id, 10, "User #{id}", "u#{id}@example.com", nil)
    end)

    assert %Page{entries: [], page: 3, page_size: 25, total_entries: 26, total_pages: 2} =
             UserAdministration.list_users(scope(), page: 3, page_size: 25)
  end

  test "a later page call truthfully observes a public Core User hard delete" do
    user!(1, 10, "Ada", "ada@example.com", nil)
    assert ids([]) == [1]

    assert :ok = CoreUser.delete_user(scope(), 10, 1)

    assert %Page{entries: [], total_entries: 0, total_pages: 0} =
             UserAdministration.list_users(scope())
  end

  test "rejects every malformed or unnormalized option without dynamic atoms" do
    max_page = Options.max_page()
    assert max_page == 1_000_000
    assert (max_page - 1) * 300 < 9_223_372_036_854_775_807

    malformed = [
      %{},
      [:name],
      [unknown: true],
      [page: 1, page: 2],
      [search: 1],
      [search: String.duplicate("x", 256)],
      [role_ids: :all],
      [role_ids: [0]],
      [role_ids: [1, 1]],
      [role_ids: Enum.to_list(1..101)],
      [sort_by: "name"],
      [sort_by: :password],
      [sort_dir: "asc"],
      [page: 0],
      [page: max_page + 1],
      [page_size: 1],
      [page_size: 10],
      [page_size: 30],
      [page_size: 9_999]
    ]

    Enum.each(malformed, fn options ->
      assert_raise ArgumentError, fn -> UserAdministration.list_users(scope(), options) end
    end)

    assert %Page{page: 1, page_size: 25} = UserAdministration.list_users(scope())
    assert %Page{page: 1, page_size: 300} = UserAdministration.list_users(scope(), page_size: 300)
    user!(1, 10, "Ada", "ada@example.com", nil)

    assert %Page{
             entries: [],
             page: ^max_page,
             total_entries: 1,
             total_pages: 1
           } = UserAdministration.list_users(scope(), page: max_page)
  end

  test "executes one parameterized PostgreSQL statement for a combined page snapshot" do
    user!(1, 10, "Ada", "ada@example.com", nil)
    assert {:ok, role} = custom_role!(10, "Viewer", "viewer")
    assert {:ok, :assigned} = Authz.assign_role(scope(), 10, :user, 1, role.id)

    handler_id = "user-administration-query-#{System.unique_integer([:positive])}"
    event = Repo.config()[:telemetry_prefix] ++ [:query]
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn _event, measurements, metadata, _config ->
          send(test_process, {:repo_query, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert %Page{entries: [%Entry{id: 1}], total_entries: 1} =
             UserAdministration.list_users(scope(), search: "A%", role_ids: [role.id])

    assert_receive {:repo_query, _measurements, %{query: query}}, 1_000
    refute_receive {:repo_query, _, _}, 50

    assert query =~ ~s(WITH "tenant_companies")
    assert query =~ ~s("filtered_users")
    assert query =~ ~s("user_total")
    assert query =~ ~s("page_users")
    assert query =~ ~s("page_roles")
    assert query =~ "$1"

    assert %Page{entries: [], total_entries: 1, total_pages: 1} =
             UserAdministration.list_users(scope(), page: 2, page_size: 25)

    assert_receive {:repo_query, _, %{query: out_of_range_query}}, 1_000
    refute_receive {:repo_query, _, _}, 50
    assert out_of_range_query =~ ~s("user_total")

    assert %Page{entries: [], total_entries: 0, total_pages: 0} =
             UserAdministration.list_users(scope(), search: "missing")

    assert_receive {:repo_query, _, %{query: empty_query}}, 1_000
    refute_receive {:repo_query, _, _}, 50
    assert empty_query =~ ~s("user_total")
  end

  defp scope(tenant_id \\ 1) do
    Scope.for_tenant(%Identity{
      id: tenant_id,
      name: "Tenant #{tenant_id}",
      status: "active",
      is_platform_operator: false
    })
  end

  defp user!(id, company_id, name, email, created_at) do
    UserFixtures.insert_user!(%{
      id: id,
      company_id: company_id,
      name: name,
      email: email,
      password_hash: "not-used"
    })

    SQL.query!(Repo, "UPDATE users SET created_at = $1 WHERE id = $2", [created_at, id])
  end

  defp ids(options),
    do: UserAdministration.list_users(scope(), options).entries |> Enum.map(& &1.id)

  defp custom_role!(company_id, name, code) do
    Authz.create_role(scope(), company_id, %{name: name, code: code})
  end

  defp archive_company!(id) do
    SQL.query!(Repo, "UPDATE companies SET deleted_at = now() WHERE id = $1", [id])
  end

  defp move_role_to_missing_company!(role_id, company_id) do
    SQL.query!(Repo, "UPDATE base_authz_roles SET company_id = $1 WHERE id = $2", [
      company_id,
      role_id
    ])
  end

  defp make_assignment_role_missing!(role_id) do
    SQL.query!(
      Repo,
      "ALTER TABLE base_authz_principal_roles DROP CONSTRAINT base_authz_principal_roles_role_id_fkey",
      []
    )

    SQL.query!(Repo, "DELETE FROM base_authz_roles WHERE id = $1", [role_id])
  end

  defp corrupt_role_identity!(role_id, company_id, is_system) do
    SQL.query!(
      Repo,
      "UPDATE base_authz_roles SET company_id = $1, is_system = $2 WHERE id = $3",
      [
        company_id,
        is_system,
        role_id
      ]
    )
  end
end
