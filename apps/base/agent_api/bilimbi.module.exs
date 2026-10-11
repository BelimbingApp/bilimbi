[
  id: "base/agent_api",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_agent_api,
  namespace: Bilimbi.Base.AgentApi,
  dependencies: [
    "base/authz",
    "base/database",
    "base/module_registry",
    "base/settings",
    "base/tenancy"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_261_011_140_000 => :bilimbi_only},
  web: nil,
  schema_contract: Bilimbi.Base.AgentApi.SchemaContract,
  contribution_provider: Bilimbi.Base.AgentApi.Contributions,
  dev_seed: nil
]
