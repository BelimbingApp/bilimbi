defmodule Bilimbi.Core.Compatibility.MigrationProvenance do
  @moduledoc false

  # The migration ledger records only a version. A mounted Domain or
  # Extension can leave the composition, and its applied versions stay in the
  # ledger because unmounting never reverses a migration or deletes its data.
  # This table records who owned each applied version -- stable module ID,
  # layer, disposition, and the file's checksum -- so the ledger can tell a
  # retired optional migration from an unexplained one, and a remount can be
  # compared with what was applied.
  #
  # It is lifecycle bookkeeping beside the ledger, not business data: a raw
  # table name, so the repo's write capture leaves it alone (ADR 0002, ADR
  # 0013).

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Ecto.Adapters.SQL

  @table "bilimbi_migration_provenance"
  @optional_layers ["domain", "extension"]

  @columns %{
    "version" => "bigint",
    "owner_id" => "character varying",
    "owner_layer" => "character varying",
    "disposition" => "character varying",
    "checksum" => "character varying",
    "recorded_at" => "timestamp without time zone"
  }

  @doc """
  Retained provenance keyed by version, or an empty map before any is recorded.
  """
  @spec fetch(Ecto.Repo.t(), String.t()) :: %{integer() => map()}
  def fetch(repo, schema) do
    case SQL.query!(repo, "SELECT to_regclass($1)::text", ["#{schema}.#{@table}"]).rows do
      [[nil]] ->
        %{}

      [[_table]] ->
        SQL.query!(
          repo,
          "SELECT version, owner_id, owner_layer, disposition, checksum FROM #{qualified(schema)}",
          []
        ).rows
        |> Map.new(fn [version, owner_id, owner_layer, disposition, checksum] ->
          {version,
           %{
             owner_id: owner_id,
             owner_layer: owner_layer,
             disposition: disposition,
             checksum: checksum
           }}
        end)
    end
  end

  @doc """
  Explains every recorded version, returning one message per version it cannot.

  A recorded version that no installed migration ships is accepted only when
  its provenance names a Domain or Extension owner that is no longer installed.
  A recorded version an installed module ships must match its provenance's
  owner and disposition, and an optional owner's file must match its checksum,
  so a remount cannot substitute a different migration under an applied version.
  """
  @spec conflicts([map()], [integer()], %{integer() => map()}, [String.t()]) :: [String.t()]
  def conflicts(migrations, versions, provenance, installed_ids) do
    by_version = Map.new(migrations, &{&1.version, &1})

    Enum.flat_map(versions, fn version ->
      case {Map.fetch(by_version, version), Map.fetch(provenance, version)} do
        {:error, :error} ->
          ["version #{version} is recorded but no installed module owns it"]

        {:error, {:ok, retained}} ->
          retired_conflicts(version, retained, installed_ids)

        {{:ok, _migration}, :error} ->
          []

        {{:ok, migration}, {:ok, retained}} ->
          installed_conflicts(migration, retained)
      end
    end)
  end

  defp retired_conflicts(version, retained, installed_ids) do
    cond do
      retained.owner_id in installed_ids ->
        ["version #{version} is recorded for #{retained.owner_id}, which no longer ships it"]

      retained.owner_layer not in @optional_layers ->
        [
          "version #{version} is recorded for #{retained.owner_id}, a #{retained.owner_layer} " <>
            "module that is not installed; only a Domain or Extension can be unmounted"
        ]

      true ->
        []
    end
  end

  defp installed_conflicts(migration, retained) do
    owner = "#{migration.owner_id} (#{migration.owner_layer})"
    recorded_owner = "#{retained.owner_id} (#{retained.owner_layer})"

    [
      {recorded_owner != owner,
       "version #{migration.version} was applied by #{recorded_owner}, but #{owner} ships it"},
      {retained.disposition != Atom.to_string(migration.disposition),
       "version #{migration.version} was applied as #{retained.disposition}, " <>
         "but #{migration.owner_id} declares #{migration.disposition}"},
      {optional?(migration) and retained.checksum != migration.checksum,
       "version #{migration.version} of #{migration.owner_id} differs from the file that was applied"}
    ]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Records provenance for every installed migration the ledger has applied.

  A Base or Core owner is recompiled with the Platform, so its checksum is
  refreshed; an optional owner's row only ever changes when the version was
  pending, because `conflicts/4` refuses a mismatched applied one first.
  """
  @spec record!(Ecto.Repo.t(), String.t(), [map()], [integer()]) :: :ok
  def record!(repo, schema, migrations, applied_versions) do
    ensure_table!(repo, schema)
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    rows =
      for migration <- migrations, migration.version in applied_versions do
        %{
          version: migration.version,
          owner_id: migration.owner_id,
          owner_layer: Atom.to_string(migration.owner_layer),
          disposition: Atom.to_string(migration.disposition),
          checksum: migration.checksum,
          recorded_at: now
        }
      end

    {_count, _} =
      repo.insert_all(@table, rows,
        prefix: schema,
        on_conflict: {:replace, [:owner_id, :owner_layer, :disposition, :checksum, :recorded_at]},
        conflict_target: [:version]
      )

    :ok
  end

  @spec checksum(String.t()) :: String.t()
  def checksum(path) do
    :sha256 |> :crypto.hash(File.read!(path)) |> Base.encode16(case: :lower)
  end

  defp optional?(migration), do: Atom.to_string(migration.owner_layer) in @optional_layers

  defp ensure_table!(repo, schema) do
    SQL.query!(
      repo,
      """
      CREATE TABLE IF NOT EXISTS #{qualified(schema)} (
        version bigint PRIMARY KEY,
        owner_id varchar(255) NOT NULL,
        owner_layer varchar(20) NOT NULL,
        disposition varchar(40) NOT NULL,
        checksum varchar(64) NOT NULL,
        recorded_at timestamp(0) without time zone NOT NULL
      )
      """,
      []
    )

    actual =
      SQL.query!(
        repo,
        """
        SELECT column_name, data_type FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = $2
        """,
        [schema, @table]
      ).rows
      |> Map.new(fn [name, type] -> {name, type} end)

    unless actual == @columns do
      raise ArgumentError,
            "#{@table} shape drift: expected #{inspect(@columns)}, found #{inspect(actual)}"
    end
  end

  defp qualified(schema) do
    "#{SchemaVerifier.quote_identifier!(schema)}.#{SchemaVerifier.quote_identifier!(@table)}"
  end
end
