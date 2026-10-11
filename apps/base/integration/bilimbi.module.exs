[
  id: "base/integration",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_integration,
  namespace: Bilimbi.Base.Integration,
  dependencies: [
    "base/audit",
    "base/authz",
    "base/database",
    "base/grid",
    "base/module_registry",
    "base/schedule",
    "base/settings",
    "base/tenancy",
    "base/ui"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_261_011_100_000 => :compatible_baseline,
    20_261_011_100_001 => :bilimbi_only
  },
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Base.Integration.SchemaContract,
  contribution_provider: Bilimbi.Base.Integration.Contributions,
  dev_seed: nil
]
