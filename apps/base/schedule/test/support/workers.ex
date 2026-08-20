defmodule Bilimbi.Base.Schedule.TestWorker do
  @moduledoc false

  use Bilimbi.Base.Schedule.Worker,
    id: "test/schedule",
    max_attempts: 2

  @impl true
  def validate_scheduled_args(%{"value" => value}) when is_integer(value),
    do: {:ok, %{"value" => value}}

  def validate_scheduled_args(_args), do: {:error, :invalid_value}

  @impl true
  def handle_scheduled_job(%{"value" => _value}, _execution), do: :ok
end

defmodule Bilimbi.Base.Schedule.RetryOnceTestWorker do
  @moduledoc false

  use Bilimbi.Base.Schedule.Worker,
    id: "test/schedule-retry-once",
    max_attempts: 2

  @impl true
  def validate_scheduled_args(%{}), do: {:ok, %{}}

  @impl true
  def handle_scheduled_job(_args, %{attempt: 1}), do: raise("test worker crash")
  def handle_scheduled_job(_args, %{attempt: 2}), do: :ok
end
