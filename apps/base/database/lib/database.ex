defmodule Bilimbi.Base.Database do
  @moduledoc """
  Owns Bilimbi's shared Ecto repository and database compatibility utilities.

  Business modules depend on this lower-level Base module instead of depending
  on the Base composition application, keeping the dependency graph acyclic.
  """

  alias Bilimbi.Base.Database.ProductionSeed
  alias Bilimbi.Base.Database.ProductionSeeds
  alias Bilimbi.Base.Database.QueryExecutor
  alias Bilimbi.Base.Repo

  @doc "Builds a validated production-seed definition from an installed module."
  @spec production_seed!(atom(), String.t(), ProductionSeed.callback(), keyword()) ::
          ProductionSeed.t()
  def production_seed!(otp_app, local_id, callback, opts \\ []) do
    ProductionSeed.for_module!(otp_app, local_id, callback, opts)
  end

  @doc """
  Runs production seeds through Bilimbi's durable execution ledger.

  A `:skipped` result means the callback was not invoked during this run. The
  persisted ledger state remains `:completed` for a previously completed seed;
  callbacks that themselves return `:skipped` persist that terminal state.
  """
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

  @doc """
  Executes a read-only SQL query safely with timeout, pagination, and parameter binding.
  """
  @spec execute_readonly(String.t(), map() | list(), keyword()) ::
          {:ok, QueryExecutor.result()} | {:error, String.t()}
  def execute_readonly(sql, params \\ %{}, opts \\ []) do
    QueryExecutor.execute_readonly(sql, params, opts)
  end

  @doc """
  Extracts named parameters (`:param_name`) from raw SQL text.
  """
  @spec extract_named_parameters(String.t()) :: [String.t()]
  def extract_named_parameters(sql) do
    QueryExecutor.extract_named_parameters(sql)
  end
end
