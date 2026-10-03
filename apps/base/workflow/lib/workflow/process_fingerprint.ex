defmodule Bilimbi.Base.Workflow.ProcessFingerprint do
  @moduledoc false
  # Belimbing v1 hashes ordered key/version/steps, with recursively sorted
  # input/metadata objects and preserved list order. A saved fingerprint is
  # never replaced. Unsupported legacy float serialization fails explicitly;
  # owners can use :bilimbi_v1 on a new definition version for floating values.
  # No PHP class name in a definition is executable.

  def digest(definition) do
    steps = Enum.map(definition.steps, &step/1)

    document =
      object([{"key", definition.key}, {"version", definition.version}, {"steps", steps}])
      |> encode()

    document =
      if definition.fingerprint_format == :bilimbi_v1,
        do: ["bilimbi_v1:", document],
        else: document

    :crypto.hash(:sha256, IO.iodata_to_binary(document)) |> Base.encode16(case: :lower)
  end

  defp step(step) do
    dependencies =
      Enum.map(step.dependencies, fn dependency ->
        object([
          {"step_key", dependency.step_key},
          {"acceptable_outcomes", dependency.acceptable_outcomes}
        ])
      end)

    object([
      {"key", step.key},
      {"label", step.label},
      {"dependencies", array(dependencies)},
      {"dependency_mode", step.dependency_mode},
      {"required_signal", step.required_signal},
      {"delay_seconds", step.delay_seconds},
      {"max_attempts", step.max_attempts},
      {"input", step.input},
      {"executor_key", step.executor_key},
      {"metadata", step.metadata},
      {"priority", step.priority},
      {"input_ref", step.input_ref},
      {"result_ref", step.result_ref}
    ])
  end

  # Encoded containers carry a tagged tuple so scalar strings are encoded once.
  defp object(pairs) do
    {:encoded,
     [
       "{",
       Enum.intersperse(
         Enum.map(pairs, fn {key, value} -> [string(key), ":", encode(value)] end),
         ","
       ),
       "}"
     ]}
  end

  defp array(values),
    do: {:encoded, ["[", Enum.intersperse(Enum.map(values, &encode/1), ","), "]"]}

  defp encode({:encoded, bytes}), do: bytes

  defp encode(value) when is_map(value),
    do: value |> Enum.sort_by(&elem(&1, 0)) |> object() |> encode()

  defp encode(value) when is_list(value), do: value |> array() |> encode()
  defp encode(value) when is_binary(value), do: string(value)
  defp encode(nil), do: "null"
  defp encode(value), do: :json.encode(value)

  defp string(value) do
    value
    |> :json.encode()
    |> IO.iodata_to_binary()
    |> String.replace("\u2028", "\\u2028")
    |> String.replace("\u2029", "\\u2029")
  end
end
