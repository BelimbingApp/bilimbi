defmodule Bilimbi.Base.Settings.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings.Cache
  alias Bilimbi.Base.Settings.Schema
  alias Bilimbi.Base.Settings.Scope
  alias Ecto.Adapters.SQL

  # Stores a plain override row without the definition's write validation, so
  # a test can stand in for a value that predates validation or was adopted
  # from Belimbing at cutover. `Settings.put/3` refuses such a value.
  def put_stored_value!(key, value, scope \\ nil) do
    {scope_type, scope_id} = Scope.database_identity(scope)

    row =
      %{key: key, value: value, is_encrypted: false, scope_type: scope_type, scope_id: scope_id}
      |> Schema.changeset()
      |> Repo.insert!()

    Cache.invalidate(key, scope_type, scope_id)
    row
  end

  # Idempotent on purpose: `BilimbiWeb.ConnCase` creates this table for every
  # web test so that a settings call never raises `undefined_table` and gets
  # swallowed by a caller's rescue (#359), while suites that predate that call
  # it themselves. Both paths have to be able to run.
  def create_settings_table! do
    # Sandbox rollback resets rows, but the node-local cache outlives the test.
    # Clear on exit too, including before a following pre-provisioning test
    # that deliberately does not create the settings table.
    Cache.clear()
    ExUnit.Callbacks.on_exit(&Cache.clear/0)

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
