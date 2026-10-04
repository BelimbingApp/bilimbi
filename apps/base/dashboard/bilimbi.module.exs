[
  id: "base/dashboard",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_dashboard,
  namespace: Bilimbi.Base.Dashboard,
  dependencies: ["base/module_registry", "base/settings", "base/ui"],
  migrations: nil,
  web: "priv/web_routes.exs",
  schema_contract: nil,
  contribution_provider: nil,
  dev_seed: nil
]
