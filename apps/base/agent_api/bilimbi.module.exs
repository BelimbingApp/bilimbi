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
    "base/tenancy"
  ],
  migrations: nil,
  web: nil,
  schema_contract: nil,
  contribution_provider: nil,
  dev_seed: nil
]
