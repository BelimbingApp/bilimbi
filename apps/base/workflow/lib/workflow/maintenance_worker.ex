defmodule Bilimbi.Base.Workflow.MaintenanceWorker do
  @moduledoc false
  # Belimbing's `blb:workflow:reconcile` ran every minute: repair durable
  # process leases and timers, then deliver due transition events. The
  # definition is contributed by `Bilimbi.Base.Workflow.Contributions` and,
  # like every schedule definition, stays disabled until an operator reviews
  # it on the Schedule board.
  use Bilimbi.Base.Schedule.Worker,
    id: "base/workflow-maintenance",
    queue: :default,
    max_attempts: 3,
    unique_period: 50

  alias Bilimbi.Base.Workflow.{Coordination, TransitionOutbox}

  @impl true
  def validate_scheduled_args(args) when args == %{}, do: {:ok, %{}}
  def validate_scheduled_args(_args), do: {:error, :invalid_args}

  @impl true
  def handle_scheduled_job(%{}, _execution) do
    try do
      {:ok, _runs} = Coordination.sweep([])
    after
      {:ok, _events} = TransitionOutbox.deliver_due(limit: 100)
    end

    :ok
  end
end
