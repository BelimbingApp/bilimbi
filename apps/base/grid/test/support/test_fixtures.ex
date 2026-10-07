defmodule Bilimbi.Base.Grid.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.TestCompanyDirectory
  alias Bilimbi.Base.Grid.TestSources
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope
  alias Ecto.Adapters.SQL

  @descriptor %{id: "base/grid", otp_app: :bilimbi_base_grid}

  def descriptor, do: @descriptor

  def create_grid_tables! do
    for statement <- [
          """
          CREATE TEMPORARY TABLE grid_test_countries (
            code varchar(2) PRIMARY KEY,
            name varchar(255) NOT NULL,
            population bigint
          ) ON COMMIT PRESERVE ROWS
          """,
          """
          CREATE TEMPORARY TABLE grid_test_customers (
            id bigserial PRIMARY KEY,
            tenant_id bigint NOT NULL,
            name varchar(255) NOT NULL,
            country_code varchar(2)
          ) ON COMMIT PRESERVE ROWS
          """,
          """
          CREATE TEMPORARY TABLE grid_test_orders (
            id bigserial PRIMARY KEY,
            tenant_id bigint NOT NULL,
            label varchar(255) NOT NULL,
            amount numeric(12,2),
            status varchar(20) NOT NULL DEFAULT 'open',
            placed_at timestamp(0) without time zone,
            customer_id bigint
          ) ON COMMIT PRESERVE ROWS
          """,
          """
          CREATE TEMPORARY TABLE grid_test_lines (
            id bigserial PRIMARY KEY,
            order_id bigint NOT NULL,
            sku varchar(64) NOT NULL,
            qty integer NOT NULL,
            price numeric(12,2) NOT NULL,
            created_at timestamp(0) without time zone
          ) ON COMMIT PRESERVE ROWS
          """,
          """
          CREATE TEMPORARY TABLE grid_test_tags (
            id bigserial PRIMARY KEY,
            name varchar(64) NOT NULL
          ) ON COMMIT PRESERVE ROWS
          """,
          """
          CREATE TEMPORARY TABLE grid_test_order_tags (
            order_id bigint NOT NULL,
            tag_id bigint NOT NULL
          ) ON COMMIT PRESERVE ROWS
          """,
          "CREATE TEMPORARY TABLE grid_test_metrics (order_id bigint PRIMARY KEY, " <>
            Enum.map_join(1..60, ", ", &"m#{&1} integer") <> ") ON COMMIT PRESERVE ROWS"
        ] do
      SQL.query!(Repo, statement, [])
    end

    :ok
  end

  def insert_country!(code, name, population \\ nil) do
    SQL.query!(
      Repo,
      "INSERT INTO grid_test_countries (code, name, population) VALUES ($1, $2, $3)",
      [
        code,
        name,
        population
      ]
    )
  end

  def insert_customer!(id, tenant_id, name, country_code) do
    SQL.query!(
      Repo,
      "INSERT INTO grid_test_customers (id, tenant_id, name, country_code) VALUES ($1, $2, $3, $4)",
      [id, tenant_id, name, country_code]
    )
  end

  def insert_order!(id, tenant_id, label, opts \\ []) do
    SQL.query!(
      Repo,
      """
      INSERT INTO grid_test_orders (id, tenant_id, label, amount, status, placed_at, customer_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      """,
      [
        id,
        tenant_id,
        label,
        Keyword.get(opts, :amount),
        Keyword.get(opts, :status, "open"),
        Keyword.get(opts, :placed_at),
        Keyword.get(opts, :customer_id)
      ]
    )
  end

  def insert_line!(order_id, sku, qty, price, created_at \\ nil) do
    SQL.query!(
      Repo,
      "INSERT INTO grid_test_lines (order_id, sku, qty, price, created_at) VALUES ($1, $2, $3, $4, $5)",
      [order_id, sku, qty, price, created_at]
    )
  end

  def insert_tag!(id, name) do
    SQL.query!(Repo, "INSERT INTO grid_test_tags (id, name) VALUES ($1, $2)", [id, name])
  end

  def tag_order!(order_id, tag_id) do
    SQL.query!(Repo, "INSERT INTO grid_test_order_tags (order_id, tag_id) VALUES ($1, $2)", [
      order_id,
      tag_id
    ])
  end

  @doc """
  Two tenants' worth of the test domain. Tenant 1 has two customers in two
  countries, three orders (one without a customer, one whose customer is in
  tenant 2), lines on two of them and tags on one. Tenant 2 has one customer
  and one order.
  """
  def seed! do
    insert_country!("MY", "Malaysia", 34_000_000)
    insert_country!("SG", "Singapore", 6_000_000)
    insert_customer!(1, 1, "Alpha Trading", "MY")
    insert_customer!(2, 1, "Beta Works", "SG")
    insert_customer!(3, 2, "Gamma Other Tenant", "SG")

    insert_order!(101, 1, "Order A",
      amount: Decimal.new("100.00"),
      status: "paid",
      placed_at: ~N[2026-01-10 09:00:00],
      customer_id: 1
    )

    insert_order!(102, 1, "Order B",
      amount: Decimal.new("250.50"),
      status: "open",
      placed_at: ~N[2026-02-15 10:00:00],
      customer_id: 2
    )

    insert_order!(103, 1, "Order C",
      amount: nil,
      status: "void",
      placed_at: ~N[2026-03-01 11:00:00],
      customer_id: 3
    )

    insert_order!(201, 2, "Other tenant order",
      amount: Decimal.new("9.00"),
      status: "open",
      placed_at: ~N[2026-03-02 12:00:00],
      customer_id: 3
    )

    insert_line!(101, "SKU-1", 2, Decimal.new("10.00"), ~N[2026-01-10 09:01:00])
    insert_line!(101, "SKU-2", 3, Decimal.new("20.00"), ~N[2026-01-10 09:02:00])
    insert_line!(101, "SKU-3", 1, Decimal.new("40.00"), ~N[2026-01-10 09:03:00])
    insert_line!(102, "SKU-9", 5, Decimal.new("50.10"), ~N[2026-02-15 10:01:00])
    insert_line!(201, "SKU-X", 1, Decimal.new("9.00"), ~N[2026-03-02 12:01:00])

    insert_tag!(1, "rush")
    insert_tag!(2, "gift")
    tag_order!(101, 1)
    tag_order!(101, 2)
    tag_order!(102, 1)
    :ok
  end

  @doc """
  Installs a snapshot holding the test domain's authz capabilities and its
  grid tables, merged over the registry's empty snapshot so every other
  consumer keeps its empty shape.
  """
  def install_test_registry!(tables \\ TestSources.tables()) do
    authz =
      Authz.ContributionValidator.validate_contributions!([
        %{
          descriptor: @descriptor,
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["view", "manage"],
            capabilities: TestSources.capabilities(),
            roles: %{},
            company_directory: TestCompanyDirectory
          }
        }
      ])

    grid =
      Grid.ContributionValidator.validate_contributions!([
        %{descriptor: @descriptor, payload: tables}
      ])

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "grid-test",
      consumers: Map.merge(ContributionRegistry.build!([]).consumers, %{authz: authz, grid: grid})
    })
  end

  @doc "A system scope for a tenant, with no tenants table behind it."
  def system_scope(tenant_id) do
    Scope.for_tenant(%Identity{
      id: tenant_id,
      name: "Tenant #{tenant_id}",
      status: "active",
      is_platform_operator: false
    })
  end

  @doc "A tenant-1 user (7, company 10) signed in with these capabilities granted."
  def user_scope(capabilities) when is_list(capabilities) do
    system = system_scope(1)

    for capability <- capabilities do
      {:ok, :stored} = Authz.put_principal_capability(system, 10, :user, 7, capability, true)
    end

    Authentication.sign_in(system, 7, 10)
  end

  @doc "A tenant-2 user (8, company 20): a different tenant, the same grants."
  def other_tenant_scope(capabilities) when is_list(capabilities) do
    system = system_scope(2)

    for capability <- capabilities do
      {:ok, :stored} = Authz.put_principal_capability(system, 20, :user, 8, capability, true)
    end

    Authentication.sign_in(system, 8, 20)
  end
end
