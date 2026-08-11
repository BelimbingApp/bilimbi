defmodule Bilimbi.Base.Repo do
  use Ecto.Repo,
    otp_app: :base,
    adapter: Ecto.Adapters.Postgres
end
