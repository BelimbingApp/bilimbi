[
  id: "base/session",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_session,
  namespace: Bilimbi.Base.Session,
  dependencies: ["base/database", "base/module_registry", "base/principal_directory", "base/ui"],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_260_811_093_950 => :compatible_baseline},
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Base.Session.SchemaContract,
  contribution_provider: Bilimbi.Base.Session.Contributions
]
