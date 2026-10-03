defmodule Bilimbi.Base.Workflow.ProcessDefinition do
  @moduledoc false
  alias Bilimbi.Base.Workflow.{JSON, ProcessFingerprint}

  def validate!(definition) do
    keys!(definition, [:key, :version, :subject, :adapter, :steps])
    key!(definition.key)
    key!(definition.subject)
    integer!(definition.version, 1)

    unless is_list(definition.steps) and definition.steps != [],
      do: invalid!("steps must be nonempty")

    steps = Enum.map(definition.steps, &step!/1)
    distinct!(Enum.map(steps, & &1.key))
    by_key = Map.new(steps, &{&1.key, &1})

    for step <- steps, dependency <- step.dependencies do
      unless dependency.step_key != step.key and Map.has_key?(by_key, dependency.step_key),
        do: invalid!("invalid dependency #{dependency.step_key}")
    end

    _ =
      Enum.reduce(steps, MapSet.new(), fn step, visited ->
        visit!(by_key, step.key, MapSet.new(), visited)
      end)

    if Enum.any?(steps, &(float?(&1.input) or float?(&1.metadata))),
      do: invalid!("legacy_v1 cannot fingerprint floats exactly; use integers or strings")

    if Enum.any?(steps, &(numeric_keys?(&1.input) or numeric_keys?(&1.metadata))),
      do: invalid!("legacy_v1 cannot fingerprint numeric object keys exactly; use lists")

    definition = %{definition | steps: steps}
    Map.put(definition, :fingerprint, ProcessFingerprint.digest(definition))
  end

  defp step!(step) do
    keys!(step, [
      :key,
      :label,
      :dependencies,
      :dependency_mode,
      :required_signal,
      :delay_seconds,
      :max_attempts,
      :input,
      :executor_key,
      :metadata,
      :priority,
      :input_ref,
      :result_ref
    ])

    key!(step.key)
    text!(step.label)

    step =
      Map.merge(
        %{
          dependencies: [],
          dependency_mode: "all",
          required_signal: nil,
          delay_seconds: 0,
          max_attempts: 1,
          input: [],
          executor_key: step.key,
          metadata: [],
          priority: 0,
          input_ref: nil,
          result_ref: nil
        },
        step
      )

    text!(step.executor_key)
    unless step.dependency_mode in ["all", "any"], do: invalid!("invalid dependency mode")
    integer!(step.delay_seconds, 0)
    integer!(step.max_attempts, 1)

    unless is_integer(step.priority) and step.priority in -2_147_483_648..2_147_483_647,
      do: invalid!("invalid priority")

    for field <- [:required_signal, :input_ref, :result_ref],
        value = Map.fetch!(step, field),
        not is_nil(value),
        do: text!(value)

    unless is_list(step.dependencies), do: invalid!("dependencies must be a list")
    dependencies = Enum.map(step.dependencies, &dependency!/1)
    distinct!(Enum.map(dependencies, & &1.step_key))

    for field <- [:input, :metadata] do
      value = Map.fetch!(step, field)

      unless (is_map(value) or is_list(value)) and match?({:ok, _}, JSON.cast(value)),
        do: invalid!("invalid #{field}")
    end

    %{step | dependencies: dependencies}
  end

  defp dependency!(dependency) do
    keys!(dependency, [:step_key, :acceptable_outcomes])
    key!(dependency.step_key)
    outcomes = Map.get(dependency, :acceptable_outcomes, ["completed"])
    unless is_list(outcomes) and outcomes != [], do: invalid!("outcomes must be nonempty")
    Enum.each(outcomes, &text!/1)
    Map.put(dependency, :acceptable_outcomes, outcomes)
  end

  defp visit!(steps, key, visiting, visited) do
    cond do
      MapSet.member?(visiting, key) ->
        invalid!("dependency cycle at #{key}")

      MapSet.member?(visited, key) ->
        visited

      true ->
        visiting = MapSet.put(visiting, key)

        steps[key].dependencies
        |> Enum.reduce(visited, &visit!(steps, &1.step_key, visiting, &2))
        |> MapSet.put(key)
    end
  end

  defp float?(value) when is_float(value), do: true
  defp float?(value) when is_map(value), do: Enum.any?(value, fn {_, item} -> float?(item) end)
  defp float?(value) when is_list(value), do: Enum.any?(value, &float?/1)
  defp float?(_), do: false

  # PHP arrays coerce integer keys and may become lists after SORT_REGULAR;
  # Elixir string-key maps cannot truthfully reproduce that array identity.
  defp numeric_keys?(value) when is_map(value),
    do:
      Enum.any?(value, fn {key, item} ->
        match?({_, ""}, Float.parse(String.trim(key))) or numeric_keys?(item)
      end)

  defp numeric_keys?(value) when is_list(value), do: Enum.any?(value, &numeric_keys?/1)
  defp numeric_keys?(_), do: false

  defp keys!(map, allowed) when is_map(map) and not is_struct(map) do
    unless Map.keys(map) -- allowed == [], do: invalid!("unknown process fields")
  end

  defp keys!(_, _), do: invalid!("expected a plain process map")

  defp key!(value) do
    text!(value)
    unless Regex.match?(~r/\A[a-z0-9][a-z0-9._-]*\z/, value), do: invalid!("invalid process key")
  end

  defp text!(value) do
    unless is_binary(value) and String.trim(value) != "" and byte_size(value) <= 255 and
             String.valid?(value),
           do: invalid!("expected a nonempty string of at most 255 bytes")
  end

  defp integer!(value, minimum) do
    unless is_integer(value) and value >= minimum and value <= 2_147_483_647,
      do: invalid!("invalid process integer")
  end

  defp distinct!(keys),
    do: if(length(keys) != length(Enum.uniq(keys)), do: invalid!("duplicate process entries"))

  defp invalid!(message), do: raise(ArgumentError, "invalid workflow contribution: #{message}")
end
