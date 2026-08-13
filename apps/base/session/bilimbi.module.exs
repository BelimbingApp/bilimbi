[
  id: "base/session",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_session,
  namespace: Bilimbi.Base.Session,
  dependencies: ["base/database", "base/module_registry", "base/ui"],
  migrations: "priv/repo/migrations",
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Base.Session.SchemaContract,
  contribution_provider: Bilimbi.Base.Session.Contributions
]
