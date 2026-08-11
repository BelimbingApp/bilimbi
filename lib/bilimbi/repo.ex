defmodule Bilimbi.Repo do
  use Ecto.Repo,
    otp_app: :bilimbi,
    adapter: Ecto.Adapters.Postgres
end
