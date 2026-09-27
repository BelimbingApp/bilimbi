[
  id: "base/tiling",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_tiling,
  namespace: Bilimbi.Base.Tiling,
  dependencies: ["base/menu", "base/module_registry", "base/settings", "base/ui"],
  migrations: nil,
  web: "priv/web_routes.exs",
  schema_contract: nil,
  contribution_provider: Bilimbi.Base.Tiling.Contributions,
  dev_seed: nil
]
