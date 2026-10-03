defmodule Bilimbi.Base.Session.ExpiryWorker do
  @moduledoc false

  use Bilimbi.Base.Schedule.Worker,
    id: "base/session-expiry",
    queue: :default,
    max_attempts: 5,
    unique_period: 240

  @impl true
  def validate_scheduled_args(args) when args == %{}, do: {:ok, %{}}
  def validate_scheduled_args(_args), do: {:error, :invalid_args}

  @impl true
  def handle_scheduled_job(%{}, _execution) do
    lifetime_minutes = Bilimbi.Base.Settings.get("session.lifetime_minutes")
    cutoff = System.system_time(:second) - lifetime_minutes * 60
    Bilimbi.Base.Session.prune_expired(cutoff)
    :ok
  end
end
