defmodule Bilimbi.Base.Artifacts.MigrationGuardTest do
  @moduledoc """
  Proves the retention guard from the shipped migrations, not from the test
  fixture's copy of their DDL: the owned migrations run into a real schema and
  PostgreSQL itself refuses the writes the contract forbids.
  """
  use ExUnit.Case, async: false

  import Bilimbi.Base.Database.LockSchema

  alias Bilimbi.Base.Artifacts.Migrations.{AddRetention, CreateArtifacts}
  alias Bilimbi.Base.Artifacts.SchemaContract
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Ecto.Adapters.SQL

  setup do
    # Migrations are not compiled into the application; load the shipped files.
    for path <- Path.wildcard(Path.expand("../priv/repo/migrations/*.exs", __DIR__)),
        do: Code.require_file(path)

    schema = create!("artifacts_guard")

    on_schema!(schema, fn ->
      TenancyFixtures.create_tenants_table!(persistent: true)
      TenancyFixtures.insert_tenant!(%{id: 41})
    end)

    # The migrator locks on one connection and migrates on another, so it
    # runs on a repo with its own pool rather than the test's checkout.
    repo = start_isolated_repo!()

    Ecto.Migrator.run(
      Repo,
      [{20_260_930_120_000, CreateArtifacts}, {20_261_013_090_000, AddRetention}],
      :up,
      all: true,
      log: false,
      prefix: schema,
      dynamic_repo: repo
    )

    %{schema: schema, repo: repo, prefix: SchemaVerifier.quote_identifier!(schema)}
  end

  test "the migrated structure matches the contract and the guards refuse", c do
    assert :ok = SchemaContract.verify_invariants(c.repo, prefix: c.schema)
    artifacts = c.prefix <> ".base_artifacts"
    events = c.prefix <> ".base_artifact_retention_events"
    id = Ecto.UUID.generate()

    SQL.query!(
      c.repo,
      """
      INSERT INTO #{artifacts}
        (id, tenant_id, company_id, owner_id, owner_adapter, subject, kind, content_type,
         byte_size, sha256, storage_root, expires_at, retain_until, ready_at,
         inserted_at, updated_at)
      VALUES ($1, 41, 51, 'test/documents', 'Owner', 'subject', 'kind', 'text/plain',
         5, repeat('a', 64), '/private', NULL, timezone('UTC', now()) + interval '7 years',
         timezone('UTC', now()), timezone('UTC', now()), timezone('UTC', now()))
      """,
      [Ecto.UUID.dump!(id)]
    )

    SQL.query!(
      c.repo,
      """
      INSERT INTO #{events}
        (artifact_id, tenant_id, company_id, owner_id, event, retain_until, legal_hold,
         actor_type, actor_id, recorded_at)
      VALUES ($1, 41, 51, 'test/documents', 'retained',
         timezone('UTC', now()) + interval '7 years', false, 'guest', 0, '2000-01-01')
      """,
      [Ecto.UUID.dump!(id)]
    )

    assert [[recorded_at]] = SQL.query!(c.repo, "SELECT recorded_at FROM #{events}", []).rows
    assert NaiveDateTime.diff(NaiveDateTime.utc_now(), recorded_at, :second) in -60..60

    refused = fn sql, message ->
      assert_raise Postgrex.Error, message, fn -> SQL.query!(c.repo, sql, []) end
    end

    refused.("UPDATE #{artifacts} SET deleted_at = now()", ~r/is retained/)
    refused.("UPDATE #{artifacts} SET purged_at = now()", ~r/is retained/)
    refused.("DELETE FROM #{artifacts}", ~r/is retained/)

    refused.(
      "UPDATE #{artifacts} SET retain_until = retain_until - interval '1 day'",
      ~r/cannot be shortened/
    )

    refused.(
      "UPDATE #{artifacts} SET retain_until = NULL, expires_at = now()",
      ~r/cannot be shortened/
    )

    refused.("UPDATE #{artifacts} SET expires_at = now()", ~r/retention_exclusive/)

    refused.("UPDATE #{events} SET reason = 'x'", ~r/append-only/)
    refused.("DELETE FROM #{events}", ~r/append-only/)
    refused.("TRUNCATE #{events}", ~r/append-only/)

    # Extending and holding are the allowed changes; a hold still blocks
    # deletion once retain-until has passed.
    SQL.query!(
      c.repo,
      "UPDATE #{artifacts} SET retain_until = retain_until + interval '1 day', legal_hold_at = now()",
      []
    )

    SQL.query!(
      c.repo,
      "ALTER TABLE #{artifacts} DISABLE TRIGGER base_artifacts_retention_guard",
      []
    )

    assert {:error, [drift]} = SchemaContract.verify_invariants(c.repo, prefix: c.schema)
    assert drift =~ "retention guard triggers differ"

    SQL.query!(
      c.repo,
      "UPDATE #{artifacts} SET retain_until = timezone('UTC', now()) - interval '1 day'",
      []
    )

    SQL.query!(
      c.repo,
      "ALTER TABLE #{artifacts} ENABLE TRIGGER base_artifacts_retention_guard",
      []
    )

    refused.("UPDATE #{artifacts} SET deleted_at = now()", ~r/is retained/)
    SQL.query!(c.repo, "UPDATE #{artifacts} SET legal_hold_at = NULL", [])
    SQL.query!(c.repo, "UPDATE #{artifacts} SET deleted_at = now(), purged_at = now()", [])
    refused.("DELETE FROM #{artifacts}", ~r/base_artifact_retention_events_artifact_id_fkey/)
  end

  defp start_isolated_repo! do
    name = Module.concat(__MODULE__, "Repo#{System.unique_integer([:positive, :monotonic])}")

    options =
      Repo.config()
      |> Keyword.put(:name, name)
      |> Keyword.put(:pool_size, 4)

    {Repo, options}
    |> Supervisor.child_spec(id: name)
    |> start_supervised!()

    previous = Repo.put_dynamic_repo(name)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Repo.put_dynamic_repo(previous)
    name
  end
end
