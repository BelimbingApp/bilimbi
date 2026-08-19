defmodule Bilimbi.Base.Settings.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  # Idempotent on purpose: `BilimbiWeb.ConnCase` creates this table for every
  # web test so that a settings call never raises `undefined_table` and gets
  # swallowed by a caller's rescue (#359), while suites that predate that call
  # it themselves. Both paths have to be able to run.
  def create_settings_table! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_settings (
        id bigserial PRIMARY KEY,
        key varchar(255) NOT NULL,
        value json NOT NULL,
        is_encrypted boolean NOT NULL DEFAULT false,
        scope_type varchar(50),
        scope_id bigint,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      "CREATE UNIQUE INDEX IF NOT EXISTS base_settings_key_scope_unique " <>
        "ON base_settings (key, scope_type, scope_id)",
      []
    )

    SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS base_settings_scope_type_scope_id_index " <>
        "ON base_settings (scope_type, scope_id)",
      []
    )

    SQL.query!(
      Repo,
      "CREATE UNIQUE INDEX IF NOT EXISTS base_settings_global_key_unique ON base_settings (key) " <>
        "WHERE scope_type IS NULL AND scope_id IS NULL",
      []
    )
  end
end
