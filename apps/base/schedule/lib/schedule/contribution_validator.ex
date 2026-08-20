defmodule Bilimbi.Base.Schedule.ContributionValidator do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Queue.Arguments
  alias Crontab.CronExpression.Parser

  @definition_keys [
    :args,
    :expression,
    :key,
    :misfire,
    :name,
    :overlap,
    :task_name,
    :timezone,
    :worker
  ]
  @key_pattern ~r/^[a-z0-9][a-z0-9._\/-]{0,254}$/

  @impl true
  def validate_contributions!(entries) when is_list(entries) do
    entries
    |> Enum.flat_map(&definitions!/1)
    |> Enum.reduce(%{}, fn definition, definitions ->
      case Map.fetch(definitions, definition.key) do
        :error ->
          Map.put(definitions, definition.key, definition)

        {:ok, first} ->
          invalid!(definition.owner, "key #{definition.key} is owned by #{first.owner}")
      end
    end)
  end

  defp definitions!(%{descriptor: descriptor, payload: %{definitions: definitions} = payload})
       when is_list(definitions) do
    unknown = Map.keys(payload) -- [:definitions]
    if unknown != [], do: invalid!(descriptor.id, "unknown keys: #{inspect(Enum.sort(unknown))}")
    Enum.map(definitions, &definition!(descriptor, &1))
  end

  defp definitions!(%{descriptor: descriptor, payload: payload}) when is_map(payload) do
    invalid!(descriptor.id, "definitions must be a list")
  end

  defp definitions!(%{descriptor: descriptor}) do
    invalid!(descriptor.id, "payload must be a map")
  end

  defp definition!(descriptor, attributes) when is_map(attributes) do
    unknown = Map.keys(attributes) -- @definition_keys

    if unknown != [],
      do: invalid!(descriptor.id, "definition has unknown keys: #{inspect(Enum.sort(unknown))}")

    key = bounded_string!(descriptor.id, attributes, :key, 255)

    unless Regex.match?(@key_pattern, key),
      do: invalid!(descriptor.id, "definition key #{inspect(key)} is invalid")

    expression = bounded_string!(descriptor.id, attributes, :expression, 64)
    cron = cron!(descriptor.id, expression)
    timezone = bounded_string!(descriptor.id, attributes, :timezone, 255)
    validate_timezone!(descriptor.id, timezone)

    worker = Map.get(attributes, :worker)
    validate_worker!(descriptor, worker)

    args = Map.get(attributes, :args, %{})
    unless is_map(args), do: invalid!(descriptor.id, "definition #{key} args must be a map")

    if Map.has_key?(args, "__bilimbi_schedule__"),
      do: invalid!(descriptor.id, "definition #{key} uses reserved schedule metadata")

    unless match?({:ok, _}, Arguments.validate(args)),
      do: invalid!(descriptor.id, "definition #{key} args are not bounded JSON data")

    overlap = Map.get(attributes, :overlap)

    unless overlap in [:allow, :forbid],
      do: invalid!(descriptor.id, "definition #{key} has invalid overlap policy")

    misfire = Map.get(attributes, :misfire)

    unless misfire == :coalesce,
      do: invalid!(descriptor.id, "definition #{key} must use :coalesce misfire policy")

    %Definition{
      key: key,
      name: bounded_string!(descriptor.id, attributes, :name, 255),
      expression: expression,
      cron: cron,
      timezone: timezone,
      owner: descriptor.id,
      task_name: bounded_string!(descriptor.id, attributes, :task_name, 255),
      worker: worker,
      args: args,
      overlap: overlap,
      misfire: misfire
    }
  end

  defp definition!(descriptor, _attributes),
    do: invalid!(descriptor.id, "definition must be a map")

  defp cron!(owner, expression) do
    if length(String.split(expression)) != 5 or String.starts_with?(expression, "@") do
      invalid!(owner, "expression #{inspect(expression)} must be a standard five-field cron")
    end

    case Parser.parse(expression, false, [:prior, :subsequent]) do
      {:ok, cron} -> cron
      {:error, _reason} -> invalid!(owner, "expression #{inspect(expression)} is invalid")
    end
  end

  defp validate_timezone!(owner, timezone) do
    case DateTime.now(timezone, TimeZoneInfo.TimeZoneDatabase) do
      {:ok, _datetime} ->
        :ok

      {:error, _reason} ->
        invalid!(owner, "timezone #{inspect(timezone)} is not an IANA timezone")
    end
  end

  defp validate_worker!(descriptor, worker) when is_atom(worker) do
    application_modules = Application.spec(descriptor.otp_app, :modules) || []

    unless Code.ensure_loaded?(worker) and function_exported?(worker, :__schedule_worker__, 0) and
             worker in application_modules do
      invalid!(
        descriptor.id,
        "worker #{inspect(worker)} must be a Schedule worker owned by #{descriptor.otp_app}"
      )
    end
  end

  defp validate_worker!(descriptor, worker),
    do: invalid!(descriptor.id, "worker #{inspect(worker)} is invalid")

  defp bounded_string!(owner, attributes, field, maximum) do
    value = Map.get(attributes, field)

    if is_binary(value) and String.trim(value) != "" and String.length(value) <= maximum do
      value
    else
      invalid!(
        owner,
        "definition #{field} must be a non-empty string of at most #{maximum} characters"
      )
    end
  end

  defp invalid!(owner, message),
    do: raise(ArgumentError, "schedule contribution from #{owner} #{message}")
end
