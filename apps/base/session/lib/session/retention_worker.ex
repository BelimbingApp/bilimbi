defmodule Bilimbi.Base.Session.RetentionWorker do
  @moduledoc false

  use Bilimbi.Base.Schedule.Worker,
    id: "base/session-retention",
    queue: :default,
    max_attempts: 5,
    unique_period: 3_600

  @impl true
  def validate_scheduled_args(args) when args == %{}, do: {:ok, %{}}
  def validate_scheduled_args(_args), do: {:error, :invalid_args}

  @impl true
  def handle_scheduled_job(%{}, _execution) do
    _deleted = Bilimbi.Base.Session.prune_by_retention()
    :ok
  rescue
    _error -> {:retry, :session_store_unavailable}
  catch
    :exit, _reason -> {:retry, :session_store_unavailable}
  end
end
