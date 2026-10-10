defmodule BilimbiWeb.CheckPendingMigrations do
  @moduledoc """
  Development-only plug: refuses a request with a page that names the
  installed module migrations the database lacks and the command that
  applies them, instead of the `undefined_table` a page would otherwise hit.

  `Phoenix.Ecto.CheckRepoStatus` cannot do this for Bilimbi. It reads the
  Repo application's central `priv/repo/migrations`, which Bilimbi does not
  use, and the "Run migrations" button on its page calls Ecto's plain
  migrator, around the ledger and adoption guard `mix bilimbi.migrate`
  enforces. So the endpoint keeps that plug for its database-exists check
  with an empty migration path, and this plug asks
  `Bilimbi.Core.Compatibility.pending_migrations/2`, the same answer
  `mix bilimbi.migrate` acts on. Do not point `CheckRepoStatus` at the module
  migration paths to get its button back.

  The page offers no button either: in development `mix bilimbi.server`
  migrates before it starts, and the exception message names
  `mix bilimbi.migrate` for a server that is already running. The check is
  skipped while the database cannot be reached, so the connection error
  surfaces where it happens.
  """

  @behaviour Plug

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Compatibility

  @doc """
  The `:migration_paths` the endpoint gives `Phoenix.Ecto.CheckRepoStatus`:
  none, so that plug keeps only its database-exists check and never offers
  its migrator button over Bilimbi's ledger.
  """
  @spec no_central_migrations(module()) :: []
  def no_central_migrations(_repo), do: []

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{} = conn, opts) do
    pending =
      try do
        Compatibility.pending_migrations(Repo, Keyword.take(opts, [:prefix]))
      rescue
        DBConnection.ConnectionError -> []
      end

    case pending do
      [] ->
        conn

      pending ->
        raise BilimbiWeb.PendingMigrationsError,
          pending: pending,
          unadopted: Compatibility.unadopted_belimbing?(Repo, Keyword.take(opts, [:prefix]))
    end
  end
end

defmodule BilimbiWeb.PendingMigrationsError do
  @moduledoc """
  Raised by `BilimbiWeb.CheckPendingMigrations` when installed module
  migrations are not recorded in the ledger. `Plug.Debugger` renders the
  message as the page; its status is 503, as Phoenix's own pending-migration
  error answers.
  """

  defexception [:pending, :unadopted, plug_status: 503]

  @impl Exception
  def message(%{pending: pending, unadopted: unadopted}) do
    count = length(pending)

    lines =
      Enum.map(pending, fn %{version: version, owner_id: owner_id} ->
        "  #{version}  #{owner_id}"
      end)

    noun = if count == 1, do: "migration is", else: "migrations are"

    """
    The database is behind the installed modules: #{count} #{noun} pending.

    #{next_step(unadopted)}

    #{Enum.join(lines, "\n")}
    """
  end

  defp next_step(true) do
    "This is an existing Belimbing database that Bilimbi has not adopted. " <>
      "Run `mix bilimbi.schema.verify`, `mix bilimbi.schema.adopt` and " <>
      "`mix bilimbi.cutover.remap` (dry run, then real) before `mix bilimbi.migrate` " <>
      "(docs/migrating-from-belimbing.md)."
  end

  defp next_step(false) do
    "Run `mix bilimbi.migrate` from the umbrella root, or restart `mix bilimbi.server`, " <>
      "which migrates before it serves. Development only: this check does not run in " <>
      "production, where the release migrates."
  end
end
