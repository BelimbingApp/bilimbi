[
  id: "core/agent_access",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_agent_access,
  namespace: Bilimbi.Core.AgentAccess,
  dependencies: [
    "base/database",
    "base/module_registry",
    "base/settings",
    "base/tenancy",
    "base/ui",
    "core/company",
    "core/user"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_261_011_120_000 => :bilimbi_only},
  schema_contract: Bilimbi.Core.AgentAccess.SchemaContract,
  web: "priv/web_routes.exs",
  contribution_provider: Bilimbi.Core.AgentAccess.Contributions,
  dev_seed: nil
]
