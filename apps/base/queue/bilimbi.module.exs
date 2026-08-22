[
  id: "base/queue",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_queue,
  namespace: Bilimbi.Base.Queue,
  dependencies: ["base/database", "base/module_registry"],
  migrations: "priv/repo/migrations",
  migration_dispositions: %{
    20_260_820_130_000 => :bilimbi_only
  },
  web: nil,
  schema_contract: nil,
  contribution_provider: nil,
  dev_seed: nil
]
