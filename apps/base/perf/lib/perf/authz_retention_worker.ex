defmodule Bilimbi.Base.Perf.AuthzRetentionWorker do
  @moduledoc false

  use Bilimbi.Base.Schedule.Worker,
    id: "base/authz-decision-log-retention",
    queue: :default,
    max_attempts: 5,
    unique_period: 3_600

  @impl true
  def validate_scheduled_args(args) when args == %{}, do: {:ok, %{}}
  def validate_scheduled_args(_args), do: {:error, :invalid_args}

  @impl true
  def handle_scheduled_job(%{}, _execution) do
    Bilimbi.Base.Authz.prune_decision_logs()
    :ok
  end
end
