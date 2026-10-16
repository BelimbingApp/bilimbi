[
  id: "core/person",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_person,
  namespace: Bilimbi.Core.Person,
  dependencies: [
    "base/agent_api",
    "base/audit",
    "base/authz",
    "base/database",
    "base/grid",
    "base/module_registry",
    "base/tenancy",
    "base/ui",
    "core/company"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_261_014_050_232 => :bilimbi_only,
    20_261_014_070_000 => :bilimbi_only,
    20_261_014_080_000 => :bilimbi_only,
    20_261_014_080_100 => :bilimbi_only
  },
  # Shipped as 20261014090000, which the Finance Domain's reconciliation
  # module already used; Compatibility moves a ledger row recorded under the
  # old number.
  renumbered_migrations: %{20_261_014_090_000 => 20_261_014_080_100},
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Core.Person.SchemaContract,
  contribution_provider: Bilimbi.Core.Person.Contributions,
  dev_seed: nil
]
