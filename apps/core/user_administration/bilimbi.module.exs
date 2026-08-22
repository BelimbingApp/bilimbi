[
  id: "core/user_administration",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_user_administration,
  namespace: Bilimbi.Core.UserAdministration,
  dependencies: [
    "base/authz",
    "base/database",
    "base/module_registry",
    "base/tenancy",
    "base/ui",
    "core/company",
    "core/user"
  ],
  migrations: nil,
  web: "priv/web_routes.exs",
  schema_contract: nil,
  contribution_provider: nil,
  dev_seed: nil
]
