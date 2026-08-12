defmodule Bilimbi.Base.Repo do
  use Ecto.Repo,
    otp_app: :bilimbi_base_database,
    adapter: Ecto.Adapters.Postgres
end
