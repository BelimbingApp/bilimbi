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
    20_261_014_070_000 => :bilimbi_only
  },
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Core.Person.SchemaContract,
  contribution_provider: Bilimbi.Core.Person.Contributions,
  dev_seed: nil
]
