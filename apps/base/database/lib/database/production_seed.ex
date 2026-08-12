defmodule Bilimbi.Base.Database.ProductionSeed do
  @moduledoc """
  A stable production-seed definition owned by one installed Bilimbi module.

  The durable ID is based on the module descriptor's logical ID, never its
  filesystem path or Elixir module name. Callbacks receive the shared Repo as
  their first argument and return `:ok`, `:skipped`, or `{:error, reason}`.
  """

  alias Bilimbi.Base.ModuleRegistry

  @id_pattern ~r/^[a-z0-9][a-z0-9_-]*(\/[a-z0-9][a-z0-9_-]*)+$/
  @local_id_pattern ~r/^[a-z0-9][a-z0-9_-]*(\/[a-z0-9][a-z0-9_-]*)*$/

  @enforce_keys [:id, :module_id, :module_order, :callback]
  defstruct [:id, :module_id, :module_order, :callback, dependencies: []]

  @type callback :: (Ecto.Repo.t() -> term()) | {module(), atom(), [term()]}

  @type t :: %__MODULE__{
          id: String.t(),
          module_id: String.t(),
          module_order: non_neg_integer(),
          callback: callback(),
          dependencies: [String.t()]
        }

  @doc "Builds a seed using the resolved metadata of an installed OTP app."
  @spec for_module!(atom(), String.t(), callback(), keyword()) :: t()
  def for_module!(otp_app, local_id, callback, opts \\ [])
      when is_atom(otp_app) and is_binary(local_id) do
    unless Regex.match?(@local_id_pattern, local_id) do
      raise ArgumentError, "production seed local ID is invalid: #{inspect(local_id)}"
    end

    descriptor =
      ModuleRegistry.installed_modules!()
      |> Enum.find(&(&1.otp_app == otp_app))
      |> case do
        nil -> raise ArgumentError, "#{inspect(otp_app)} has no installed Bilimbi module metadata"
        descriptor -> descriptor
      end

    new!(
      id: descriptor.id <> "/" <> local_id,
      module_id: descriptor.id,
      module_order: descriptor.order,
      callback: callback,
      dependencies: Keyword.get(opts, :dependencies, [])
    )
  end

  @doc false
  @spec new!(keyword()) :: t()
  def new!(attrs) when is_list(attrs) do
    seed = struct!(__MODULE__, attrs)
    validate!(seed)
  end

  @doc false
  @spec invoke(t(), Ecto.Repo.t()) :: term()
  def invoke(%__MODULE__{callback: callback}, repo) when is_function(callback, 1),
    do: callback.(repo)

  def invoke(%__MODULE__{callback: {module, function, args}}, repo),
    do: apply(module, function, [repo | args])

  defp validate!(seed) do
    unless is_binary(seed.id) and Regex.match?(@id_pattern, seed.id) do
      raise ArgumentError, "production seed ID is invalid: #{inspect(seed.id)}"
    end

    unless is_binary(seed.module_id) and Regex.match?(@id_pattern, seed.module_id) do
      raise ArgumentError, "production seed module ID is invalid: #{inspect(seed.module_id)}"
    end

    unless String.starts_with?(seed.id, seed.module_id <> "/") do
      raise ArgumentError, "production seed ID must be namespaced by its module ID"
    end

    unless is_integer(seed.module_order) and seed.module_order >= 0 do
      raise ArgumentError, "production seed module order must be a non-negative integer"
    end

    unless valid_callback?(seed.callback) do
      raise ArgumentError, "production seed callback must be a one-arity function or MFA"
    end

    unless is_list(seed.dependencies) and
             Enum.all?(seed.dependencies, &(is_binary(&1) and Regex.match?(@id_pattern, &1))) and
             length(seed.dependencies) == length(Enum.uniq(seed.dependencies)) do
      raise ArgumentError, "production seed dependencies must be unique stable seed IDs"
    end

    if seed.id in seed.dependencies do
      raise ArgumentError, "production seed cannot depend on itself"
    end

    seed
  end

  defp valid_callback?(callback) when is_function(callback, 1), do: true

  defp valid_callback?({module, function, args}),
    do: is_atom(module) and is_atom(function) and is_list(args)

  defp valid_callback?(_callback), do: false
end
