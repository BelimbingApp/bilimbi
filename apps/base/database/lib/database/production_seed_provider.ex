defmodule Bilimbi.Base.Database.ProductionSeedProvider do
  @moduledoc """
  Contract for installed modules that contribute production reference seeds.

  Providers are explicitly registered in their owning OTP application's
  `:bilimbi_production_seed_provider` environment. Development and demo
  fixtures do not implement this behaviour and are never auto-discovered.
  """

  alias Bilimbi.Base.Database.ProductionSeed

  @callback production_seeds() :: [ProductionSeed.t()]
end
