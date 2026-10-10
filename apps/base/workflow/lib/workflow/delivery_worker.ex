defmodule Bilimbi.Base.Workflow.DeliveryWorker do
  @moduledoc false
  # The immediate delivery attempt for one outbox row. It is enqueued inside
  # the transition's transaction, so it becomes visible only when that
  # transaction commits; a rolled-back transition leaves no job. The row is
  # the retry authority: a deferred delivery is retried by the maintenance
  # schedule, not by this job, so a deferral is still a successful job.
  use Bilimbi.Base.Queue.Worker,
    id: "base/workflow-transition-delivery",
    queue: :default,
    max_attempts: 3

  alias Bilimbi.Base.Workflow.TransitionOutbox

  @impl true
  def validate_args(%{"outbox_id" => id}) when is_integer(id) and id > 0,
    do: {:ok, %{"outbox_id" => id}}

  def validate_args(_args), do: {:error, :invalid_outbox_id}

  @impl true
  def handle_job(%{"outbox_id" => id}, _execution) do
    {:ok, _outcome} = TransitionOutbox.deliver(id)
    :ok
  end
end
