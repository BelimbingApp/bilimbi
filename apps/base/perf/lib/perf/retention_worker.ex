defmodule Bilimbi.Base.Perf.RetentionWorker do
  @moduledoc false

  use Bilimbi.Base.Schedule.Worker,
    id: "base/perf-retention",
    queue: :default,
    max_attempts: 5,
    unique_period: 3_600

  @impl true
  def validate_scheduled_args(args) when args == %{}, do: {:ok, %{}}
  def validate_scheduled_args(_args), do: {:error, :invalid_args}

  @impl true
  def handle_scheduled_job(%{}, _execution) do
    case Bilimbi.Base.Perf.prune() do
      {:ok, _deleted} -> :ok
      {:error, :unavailable} -> {:retry, :store_unavailable}
    end
  end
end
