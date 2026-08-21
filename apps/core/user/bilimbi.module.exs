[
  id: "core/user",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_user,
  namespace: Bilimbi.Core.User,
  dependencies: [
    "base/audit",
    "base/authz",
    "base/database",
    "base/locale",
    "base/module_registry",
    "base/principal_directory",
    "base/session",
    "base/settings",
    "base/tenancy",
    "base/ui",
    "core/company",
    "core/employee"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_260_813_094_500 => :compatible_baseline,
    20_260_821_213_100 => :bilimbi_only
  },
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Core.User.SchemaContract,
  contribution_provider: Bilimbi.Core.User.Contributions
]
