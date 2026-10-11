defmodule Bilimbi.Base.AgentApi.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.AgentApi.ContributionValidator
  alias Bilimbi.Base.AgentApi.TestCompanyDirectory
  alias Bilimbi.Base.AgentApi.TestOperations
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope

  @descriptor %{id: "base/agent_api", otp_app: :bilimbi_base_agent_api}

  @doc "Creates the plan storage from its owner's contract, for host and lock tests."
  def create_plan_tables!(opts \\ []) do
    alias Bilimbi.Base.Database.TestTables
    alias Bilimbi.Base.AgentApi.SchemaContract
    alias Bilimbi.Base.Repo
    alias Ecto.Adapters.SQL
    persistent = TestTables.persistent?(opts)
    [table] = SchemaContract.storage_tables()

    columns =
      Enum.map_join(table.columns, ", ", fn {name, spec} ->
        type =
          case spec.type do
            {:varchar, size} -> "varchar(#{size})"
            {:timestamp, precision} -> "timestamp(#{precision}) without time zone"
            type -> Atom.to_string(type)
          end

        name <>
          " " <>
          type <>
          if(spec.nullable, do: "", else: " NOT NULL") <>
          if(name == "id", do: " PRIMARY KEY", else: "")
      end)

    foreign_keys =
      Enum.map_join(table.foreign_keys, "", fn {name, spec} ->
        {target, columns} = spec.references

        ", CONSTRAINT #{name} FOREIGN KEY (#{Enum.join(spec.columns, ",")}) REFERENCES #{target}(#{Enum.join(columns, ",")}) ON DELETE RESTRICT"
      end)

    SQL.query!(
      Repo,
      "#{TestTables.create(persistent)} #{table.name} (#{columns}#{foreign_keys}) #{TestTables.on_commit(persistent)}",
      []
    )

    for {name, index} <- table.indexes, name != table.name <> "_pkey" do
      SQL.query!(
        Repo,
        "CREATE #{if index.unique, do: "UNIQUE ", else: ""}INDEX #{name} ON #{table.name}(#{Enum.join(index.columns, ",")})",
        []
      )
    end
  end

  def descriptor, do: @descriptor

  @doc """
  Installs the test domain's capabilities and, unless `agent_api: nil` is
  given, its operations, over the registry's empty snapshot.
  """
  def install_test_registry!(opts \\ []) do
    authz =
      Authz.ContributionValidator.validate_contributions!([
        %{
          descriptor: @descriptor,
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["view", "list", "update"],
            capabilities: TestOperations.capabilities(),
            roles: %{},
            company_directory: TestCompanyDirectory
          }
        }
      ])

    consumers =
      case Keyword.get(opts, :agent_api, TestOperations.payload()) do
        nil ->
          %{authz: authz}

        payload ->
          %{
            authz: authz,
            agent_api:
              ContributionValidator.validate_contributions!([
                %{descriptor: @descriptor, payload: payload}
              ])
          }
      end

    ContributionRegistry.put_consumers_for_test!(consumers, "agent-api-test")
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

  @doc "A tenant-1 person (user 7, company 10) signed in with these capabilities granted."
  def user_scope(capabilities) when is_list(capabilities) do
    system = system_scope(1)

    for capability <- capabilities do
      {:ok, :stored} = Authz.put_principal_capability(system, 10, :user, 7, capability, true)
    end

    Authentication.sign_in(system, 7, 10)
  end
end
