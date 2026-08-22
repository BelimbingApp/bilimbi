[
  id: "base/locale",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_locale,
  namespace: Bilimbi.Base.Locale,
  dependencies: ["base/module_registry", "base/settings"],
  migrations: nil,
  web: nil,
  schema_contract: nil,
  contribution_provider: Bilimbi.Base.Locale.Contributions,
  dev_seed: nil
]
