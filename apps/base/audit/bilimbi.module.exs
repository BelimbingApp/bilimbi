[
  id: "base/audit",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_audit,
  namespace: Bilimbi.Base.Audit,
  dependencies: ["base/database", "base/module_registry", "base/tenancy", "base/ui"],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_260_813_114_300 => :compatible_baseline},
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Base.Audit.SchemaContract,
  contribution_provider: Bilimbi.Base.Audit.Contributions
]
