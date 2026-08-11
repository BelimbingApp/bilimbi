defmodule Bilimbi.Core.MigrationTestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :base,
    adapter: Ecto.Adapters.Postgres
end
