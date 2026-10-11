defmodule Bilimbi.Base.Integration.RetentionWorker do
  @moduledoc false
  use Bilimbi.Base.Schedule.Worker,
    id: "base/integration-payload-retention",
    queue: :default,
    max_attempts: 5,
    unique_period: 3600

  @impl true
  def validate_scheduled_args(args) when args == %{}, do: {:ok, %{}}
  def validate_scheduled_args(_), do: {:error, :invalid_args}
  @impl true
  def handle_scheduled_job(%{}, _execution) do
    _pruned = Bilimbi.Base.Integration.prune_payloads()
    :ok
  rescue
    _error -> {:retry, :integration_store_unavailable}
  end
end
