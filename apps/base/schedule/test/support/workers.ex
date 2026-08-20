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
  def handle_scheduled_job(%{"value" => value}, _execution) do
    if recipient = Application.get_env(:bilimbi_base_schedule, :test_recipient) do
      send(recipient, {:schedule_business_effect, value})
    end

    :ok
  end
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

defmodule Bilimbi.Base.Schedule.FinalizeFailureTestWorker do
  @moduledoc false

  use Bilimbi.Base.Schedule.Worker,
    id: "test/schedule-finalize-failure",
    max_attempts: 2

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  @impl true
  def validate_scheduled_args(%{}), do: {:ok, %{}}

  @impl true
  def handle_scheduled_job(_args, _execution) do
    if recipient = Application.get_env(:bilimbi_base_schedule, :test_recipient) do
      send(recipient, :schedule_business_committed)
    end

    SQL.query!(
      Repo,
      "ALTER TABLE base_schedule_occurrences RENAME TO unavailable_occurrences",
      []
    )

    :ok
  end
end
