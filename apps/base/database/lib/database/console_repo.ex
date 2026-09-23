defmodule Bilimbi.Base.Database.ConsoleRepo do
  @moduledoc """
  The operator SQL console's own database connection.

  It connects as the console's select-only PostgreSQL role, so a write that
  reaches the database is refused on privileges whatever the query says and
  whatever the application checks. `read_only: true` also removes Ecto's write
  functions from this module; that is a convenience, not the boundary.
  `Bilimbi.Base.Database.ConsoleAccess` grants the role its reads and proves,
  before every console run, that the connection cannot write.

  Nothing but the console executes through this Repo. Every other read and
  write uses `Bilimbi.Base.Repo`.
  """

  use Ecto.Repo,
    otp_app: :bilimbi_base_database,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
