[
  id: "base/menu",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_menu,
  namespace: Bilimbi.Base.Menu,
  dependencies: ["base/module_registry"],
  migrations: nil,
  schema_contract: nil,
  contribution_provider: Bilimbi.Base.Menu.Contributions
]
