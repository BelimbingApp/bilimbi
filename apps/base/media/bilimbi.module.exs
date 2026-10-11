[
  id: "base/media",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_media,
  namespace: Bilimbi.Base.Media,
  dependencies: [
    "base/audit",
    "base/database",
    "base/module_registry",
    "base/settings",
    "base/tenancy",
    "base/ui"
  ],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{20_261_011_110_000 => :compatible_baseline},
  web: "priv/web_routes.exs",
  schema_contract: Bilimbi.Base.Media.SchemaContract,
  contribution_provider: Bilimbi.Base.Media.Contributions,
  dev_seed: nil
]
