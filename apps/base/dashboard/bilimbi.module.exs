[
  id: "base/dashboard",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_dashboard,
  namespace: Bilimbi.Base.Dashboard,
  dependencies: ["base/module_registry", "base/ui"],
  migrations: nil,
  web: nil,
  schema_contract: nil,
  contribution_provider: Bilimbi.Base.Dashboard.Contributions
]
