[
  id: "base/ui",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_ui,
  namespace: Bilimbi.Base.UI,
  dependencies: ["base/menu", "base/module_registry"],
  migrations: nil,
  web: "priv/web_routes.exs",
  schema_contract: nil,
  contribution_provider: Bilimbi.Base.UI.Contributions
]
