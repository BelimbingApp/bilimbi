defmodule Bilimbi.Base.Queue.TestWorkers.Success do
  @moduledoc false

  use Bilimbi.Base.Queue.Worker,
    id: "test/success",
    max_attempts: 3

  @impl true
  def validate_args(%{"value" => value}) when is_integer(value), do: {:ok, %{"value" => value}}
  def validate_args(_args), do: {:error, :invalid_value}

  @impl true
  def handle_job(_args, _execution), do: :ok
end

defmodule Bilimbi.Base.Queue.TestWorkers.Retry do
  @moduledoc false

  use Bilimbi.Base.Queue.Worker,
    id: "test/retry",
    max_attempts: 2

  @impl true
  def validate_args(%{"outcome" => outcome}) when outcome in ["retry", "cancel"],
    do: {:ok, %{"outcome" => outcome}}

  def validate_args(_args), do: {:error, :invalid_outcome}

  @impl true
  def handle_job(%{"outcome" => "retry"}, _execution), do: {:retry, :temporary_failure}
  def handle_job(%{"outcome" => "cancel"}, _execution), do: {:cancel, :permanent_failure}
end

defmodule Bilimbi.Base.Queue.TestWorkers.Unique do
  @moduledoc false

  use Bilimbi.Base.Queue.Worker,
    id: "test/unique",
    max_attempts: 3,
    unique_period: 60

  @impl true
  def validate_args(%{"business_id" => id}) when is_integer(id),
    do: {:ok, %{"business_id" => id}}

  def validate_args(_args), do: {:error, :invalid_business_id}

  @impl true
  def handle_job(_args, _execution), do: :ok
end
