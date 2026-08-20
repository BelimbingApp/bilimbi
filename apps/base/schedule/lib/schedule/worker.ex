defmodule Bilimbi.Base.Schedule.Worker do
  @moduledoc """
  Defines a capability-owned Queue worker with Schedule recording semantics.

  The owning capability validates and handles only its own arguments. Schedule
  reserves a private metadata member, verifies it against the durable occurrence,
  and records attempts without changing the business result.
  """

  @callback validate_scheduled_args(map()) :: {:ok, map()} | {:error, atom()}
  @callback handle_scheduled_job(map(), Bilimbi.Base.Queue.Execution.t()) ::
              Bilimbi.Base.Queue.Worker.result()

  defmacro __using__(opts) do
    quote do
      @behaviour Bilimbi.Base.Schedule.Worker
      use Bilimbi.Base.Queue.Worker, unquote(opts)

      @doc false
      def __schedule_worker__, do: true

      @impl Bilimbi.Base.Queue.Worker
      def validate_args(args),
        do: Bilimbi.Base.Schedule.Worker.validate_args(__MODULE__, args)

      @impl Bilimbi.Base.Queue.Worker
      def handle_job(args, execution),
        do: Bilimbi.Base.Schedule.Execution.run(__MODULE__, args, execution)
    end
  end

  @doc false
  def validate_args(worker, %{"__bilimbi_schedule__" => metadata} = args) when is_map(metadata) do
    business_args = Map.delete(args, "__bilimbi_schedule__")

    with {:ok, normalized} <- worker.validate_scheduled_args(business_args),
         true <- is_map(normalized),
         {:ok, normalized_metadata} <- validate_metadata(metadata) do
      {:ok, Map.put(normalized, "__bilimbi_schedule__", normalized_metadata)}
    else
      {:error, code} when is_atom(code) -> {:error, code}
      _invalid -> {:error, :invalid_schedule_args}
    end
  rescue
    _error -> {:error, :invalid_schedule_args}
  catch
    _kind, _reason -> {:error, :invalid_schedule_args}
  end

  def validate_args(_worker, _args), do: {:error, :missing_schedule_metadata}

  defp validate_metadata(%{
         "occurrence_id" => occurrence_id,
         "source" => source,
         "key" => key,
         "name" => name,
         "expression" => expression,
         "intended_at" => intended_at,
         "trigger" => trigger
       })
       when is_integer(occurrence_id) and occurrence_id > 0 and is_binary(source) and
              byte_size(source) in 1..40 and is_binary(key) and byte_size(key) in 1..255 and
              is_binary(name) and byte_size(name) in 1..255 and
              (is_nil(expression) or (is_binary(expression) and byte_size(expression) <= 64)) and
              trigger in ["manual", "scheduled"] do
    case DateTime.from_iso8601(intended_at) do
      {:ok, datetime, 0} ->
        {:ok,
         %{
           "occurrence_id" => occurrence_id,
           "source" => source,
           "key" => key,
           "name" => name,
           "expression" => expression,
           "intended_at" => DateTime.to_iso8601(datetime),
           "trigger" => trigger
         }}

      _invalid ->
        {:error, :invalid_schedule_time}
    end
  end

  defp validate_metadata(_metadata), do: {:error, :invalid_schedule_metadata}
end
