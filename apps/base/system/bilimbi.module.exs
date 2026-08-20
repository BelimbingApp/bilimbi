[
  id: "base/system",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_system,
  namespace: Bilimbi.Base.System,
  dependencies: [
    "base/database",
    "base/locale",
    "base/menu",
    "base/module_registry",
    "base/queue",
    "base/ui"
  ],
  migrations: nil,
  web: "priv/web_routes.exs",
  schema_contract: nil,
  contribution_provider: Bilimbi.Base.System.Contributions
]
