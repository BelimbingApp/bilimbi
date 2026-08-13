defmodule Bilimbi.Core.Compatibility.PlatformBaselineTestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :bilimbi_base_database,
    adapter: Ecto.Adapters.Postgres
end
