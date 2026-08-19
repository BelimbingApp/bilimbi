defmodule Bilimbi.Core.UserAdministration.PerformanceTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Bilimbi.Core.UserAdministration
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
    insert_company!(%{id: 10, tenant_id: 1, name: "Alpha Company", code: "alpha"})

    insert_company!(%{
      id: 11,
      tenant_id: 1,
      name: "Archived Company",
      code: "archived",
      deleted_at: ~N[2026-01-01 00:00:00]
    })

    Enum.each(1..40, fn id ->
      company_id = if rem(id, 5) == 0, do: 11, else: 10

      UserFixtures.insert_user!(%{
        id: id,
        company_id: company_id,
        name: "User #{String.pad_leading(Integer.to_string(id), 2, "0")}",
        email: "user#{String.pad_leading(Integer.to_string(41 - id), 2, "0")}@example.com",
        password_hash: "not-used"
      })

      SQL.query!(Repo, "UPDATE users SET created_at = $1 WHERE id = $2", [
        NaiveDateTime.add(~N[2026-01-01 00:00:00], id, :day),
        id
      ])
    end)

    assert {:ok, role} = Authz.create_role(scope(), 10, %{name: "Reviewer", code: "reviewer"})

    Enum.each(1..40//3, fn id ->
      assert {:ok, :assigned} = Authz.assign_role(scope(), 10, :user, id, role.id)
    end)

    %{role_id: role.id}
  end

  test "representative scenarios stay one-statement, page-bounded, and explainable", %{
    role_id: role_id
  } do
    scenarios = [
      {:unfiltered, []},
      {:selective_search, [search: "User 01%"]},
      {:nonselective_search, [search: "User %"]},
      {:name_asc, [sort_by: :name, sort_dir: :asc]},
      {:name_desc, [sort_by: :name, sort_dir: :desc]},
      {:email_asc, [sort_by: :email, sort_dir: :asc]},
      {:email_desc, [sort_by: :email, sort_dir: :desc]},
      {:company_asc, [sort_by: :company_name, sort_dir: :asc]},
      {:company_desc, [sort_by: :company_name, sort_dir: :desc]},
      {:created_asc, [sort_by: :created_at, sort_dir: :asc]},
      {:created_desc, [sort_by: :created_at, sort_dir: :desc]},
      {:role_filter, [role_ids: [role_id]]},
      {:combined, [search: "User %", role_ids: [role_id], page_size: 25]},
      {:deep_page, [page: 4, page_size: 25]},
      {:out_of_range, [page: 9, page_size: 25]}
    ]

    results = Enum.map(scenarios, fn {name, options} -> explain_scenario(name, options) end)

    assert Enum.all?(results, &(&1.query_count == 1))
    assert Enum.all?(results, &(&1.actual_rows <= &1.page_size))
    assert Enum.all?(results, &is_number(&1.execution_time_ms))
    assert Enum.all?(results, &is_integer(&1.buffer_blocks))
    assert Enum.all?(results, &(&1.temp_blocks == 0))
  end

  defp explain_scenario(name, options) do
    handler_id = "user-administration-explain-#{System.unique_integer([:positive])}"
    event = Repo.config()[:telemetry_prefix] ++ [:query]
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn _event, _measurements, metadata, _config ->
          send(test_process, {:page_query, metadata})
        end,
        nil
      )

    page = UserAdministration.list_users(scope(), options)
    :ok = :telemetry.detach(handler_id)

    assert_receive {:page_query, %{query: query, params: params}}, 1_000
    refute_receive {:page_query, _metadata}, 25

    %{rows: [[[plan]]]} =
      SQL.query!(Repo, "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " <> query, params)

    root = plan["Plan"]

    %{
      name: name,
      query_count: 1,
      page_size: max(page.page_size, 1),
      actual_rows: root["Actual Rows"],
      execution_time_ms: plan["Execution Time"],
      temp_blocks: root["Temp Read Blocks"] + root["Temp Written Blocks"],
      buffer_blocks:
        Enum.sum([
          root["Shared Hit Blocks"],
          root["Shared Read Blocks"],
          root["Local Hit Blocks"],
          root["Local Read Blocks"],
          root["Temp Read Blocks"],
          root["Temp Written Blocks"]
        ])
    }
  end

  defp scope do
    Scope.for_tenant(%Identity{
      id: 1,
      name: "Tenant one",
      status: "active",
      is_platform_operator: false
    })
  end
end
