defmodule BilimbiWeb.CheckPendingMigrationsTest do
  use BilimbiWeb.ConnCase, async: false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Compatibility
  alias BilimbiWeb.CheckPendingMigrations
  alias BilimbiWeb.PendingMigrationsError
  alias Ecto.Adapters.SQL

  @ledger "bilimbi_schema_migrations"

  # The sandbox rolls the ledger back with the test, so each test starts from
  # a ledger that records every installed migration, as a migrated
  # development database does.
  setup do
    SQL.query!(
      Repo,
      "CREATE TABLE IF NOT EXISTS #{@ledger} " <>
        "(version bigint PRIMARY KEY, inserted_at timestamp(0) without time zone NOT NULL)",
      []
    )

    for %{version: version} <- Compatibility.pending_migrations(Repo) do
      SQL.query!(
        Repo,
        "INSERT INTO #{@ledger} (version, inserted_at) VALUES ($1, now()) ON CONFLICT DO NOTHING",
        [version]
      )
    end

    assert Compatibility.pending_migrations(Repo) == []
    %{opts: CheckPendingMigrations.init([])}
  end

  test "a migrated database passes the request through", %{conn: conn, opts: opts} do
    assert CheckPendingMigrations.call(conn, opts) == conn
  end

  test "a module migration the ledger lacks is refused with the command to run", %{
    conn: conn,
    opts: opts
  } do
    [[version]] = SQL.query!(Repo, "SELECT max(version) FROM #{@ledger}", []).rows
    SQL.query!(Repo, "DELETE FROM #{@ledger} WHERE version = $1", [version])

    assert [%{version: ^version, owner_id: owner_id}] = Compatibility.pending_migrations(Repo)

    error =
      assert_raise PendingMigrationsError, fn -> CheckPendingMigrations.call(conn, opts) end

    assert Plug.Exception.status(error) == 503
    assert Plug.Exception.actions(error) == []

    message = Exception.message(error)
    assert message =~ "1 migration is pending"
    assert message =~ "#{version}  #{owner_id}"
    assert message =~ "Run `mix bilimbi.migrate` from the umbrella root"
    assert message =~ "restart `mix bilimbi.server`"
    refute message =~ "not adopted"
  end

  test "an unadopted Belimbing database is sent to adoption, not to migrate", %{
    conn: conn,
    opts: opts
  } do
    SQL.query!(Repo, "DELETE FROM #{@ledger}", [])

    SQL.query!(
      Repo,
      "CREATE TABLE migrations (id serial PRIMARY KEY, migration varchar NOT NULL, batch integer NOT NULL)",
      []
    )

    error =
      assert_raise PendingMigrationsError, fn -> CheckPendingMigrations.call(conn, opts) end

    message = Exception.message(error)
    assert message =~ "migrations are pending"
    assert message =~ "not adopted"
    assert message =~ "`mix bilimbi.schema.verify`, `mix bilimbi.schema.adopt`"
    refute message =~ "restart `mix bilimbi.server`"
  end
end
