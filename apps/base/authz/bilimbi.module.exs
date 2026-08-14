[
  id: "base/authz",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_authz,
  namespace: Bilimbi.Base.Authz,
  dependencies: [
    "base/database",
    "base/module_registry",
    "base/settings",
    "base/tenancy",
    "base/ui"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_260_811_093_953 => :compatible_baseline},
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Base.Authz.SchemaContract,
  contribution_provider: Bilimbi.Base.Authz.Contributions
]
