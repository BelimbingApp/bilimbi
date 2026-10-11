defmodule Bilimbi.Base.Workflow.TestListener do
  @moduledoc false
  # Records every delivery it receives and answers as the test configured:
  # `:ok`, `{:error, reason}`, `:raise` or `:garbage`.
  @behaviour Bilimbi.Base.Workflow.TransitionListener

  def start_link(_opts \\ []),
    do: Agent.start_link(fn -> %{mode: :ok, deliveries: []} end, name: __MODULE__)

  def child_spec(opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}

  def mode(mode), do: Agent.update(__MODULE__, &%{&1 | mode: mode})

  def deliveries, do: Agent.get(__MODULE__, & &1.deliveries) |> Enum.reverse()

  @impl true
  def handle(scope, event) do
    Agent.update(__MODULE__, fn state ->
      %{state | deliveries: [%{scope: scope, event: event} | state.deliveries]}
    end)

    case Agent.get(__MODULE__, & &1.mode) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      :raise -> raise "listener outage"
      :garbage -> :delivered
    end
  end
end
