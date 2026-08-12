defmodule Bilimbi.Base.Database do
  @moduledoc """
  Owns Bilimbi's shared Ecto repository and database compatibility utilities.

  Business modules depend on this lower-level Base module instead of depending
  on the Base composition application, keeping the dependency graph acyclic.
  """

  alias Bilimbi.Base.Database.ProductionSeed
  alias Bilimbi.Base.Database.ProductionSeeds
  alias Bilimbi.Base.Repo

  @doc "Builds a validated production-seed definition from an installed module."
  @spec production_seed!(atom(), String.t(), ProductionSeed.callback(), keyword()) ::
          ProductionSeed.t()
  def production_seed!(otp_app, local_id, callback, opts \\ []) do
    ProductionSeed.for_module!(otp_app, local_id, callback, opts)
  end

  @doc "Runs production seeds through Bilimbi's durable execution ledger."
  @spec run_production_seeds([ProductionSeed.t()], keyword()) ::
          {:ok, [map()]} | {:error, map()}
  def run_production_seeds(seeds, opts \\ []) do
    {repo, opts} = Keyword.pop(opts, :repo, Repo)
    ProductionSeeds.run(repo, seeds, opts)
  end

  @doc "Lists the persisted production-seed execution state."
  @spec list_production_seed_runs(keyword()) :: [map()]
  def list_production_seed_runs(opts \\ []) do
    {repo, opts} = Keyword.pop(opts, :repo, Repo)
    ProductionSeeds.list_runs(repo, opts)
  end
end
