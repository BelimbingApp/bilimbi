defmodule Bilimbi.Base.Workflow.TestGuard do
  @moduledoc false
  @behaviour Bilimbi.Base.Workflow.GuardAdapter
  @impl true
  def check(_scope, _subject, _edge, %{input: %{"refuse_guard" => true}}),
    do: {:error, :guard_refused}

  def check(_scope, _subject, _edge, _context), do: :ok
end
