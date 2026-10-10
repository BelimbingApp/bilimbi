defmodule Mix.Tasks.Bilimbi.Workflow.Reconcile do
  @moduledoc """
  Runs one pass of the Workflow maintenance that the schedule performs every
  minute: repairs expired leases and releases due timers on every running
  process run, then delivers due transition events from the outbox.

      mix bilimbi.workflow.reconcile [--outbox-limit 100]

  Use it when the schedule definition is still unreviewed, or to drain a
  backlog after a deployment.
  """
  use Mix.Task

  alias Bilimbi.Base.Workflow

  @shortdoc "Reconciles process runs and delivers due workflow transition events"

  @impl true
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [outbox_limit: :integer])

    if rest != [] or invalid != [],
      do: Mix.raise("usage: mix bilimbi.workflow.reconcile [--outbox-limit N]")

    Mix.Task.run("app.start")

    {:ok, runs} = Workflow.reconcile_running_runs()

    {:ok, events} =
      Workflow.deliver_transition_events(limit: Keyword.get(opts, :outbox_limit, 100))

    Mix.shell().info("Process runs reconciled: #{runs.reconciled} (skipped #{runs.skipped})")

    Mix.shell().info(
      "Transition events delivered: #{events.delivered} (deferred #{events.deferred})"
    )
  end
end
