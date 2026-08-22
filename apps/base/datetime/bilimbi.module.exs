[
  id: "base/datetime",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_datetime,
  namespace: Bilimbi.Base.DateTime,
  dependencies: ["base/locale", "base/module_registry", "base/settings", "base/ui"],
  migrations: nil,
  web: nil,
  schema_contract: nil,
  contribution_provider: Bilimbi.Base.DateTime.Contributions,
  dev_seed: nil
]
