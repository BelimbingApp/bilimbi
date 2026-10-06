[
  id: "base/grid",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_grid,
  namespace: Bilimbi.Base.Grid,
  dependencies: [
    "base/authz",
    "base/database",
    "base/module_registry",
    "base/settings",
    "base/tenancy",
    "base/ui"
  ],
  migrations: nil,
  web: nil,
  schema_contract: nil,
  contribution_provider: Bilimbi.Base.Grid.Contributions,
  dev_seed: nil
]
