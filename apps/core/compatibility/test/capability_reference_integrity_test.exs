defmodule Bilimbi.Core.CapabilityReferenceIntegrityTest do
  @moduledoc """
  Proves that literal production capability references name installed Authz
  capabilities.

  Runtime authorization intentionally fails closed for unknown keys. That is
  safe, but it also makes a typo indistinguishable from an actor lacking a real
  capability. This integration test turns that silent dead feature into a
  source-located failure.
  """

  use ExUnit.Case, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.CapabilityKey
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  @workspace_root Path.expand("../../../..", __DIR__)
  @segment ~S"[a-z][a-z0-9]*(?:-[a-z0-9]+)*"
  @capability "#{@segment}(?:\\.#{@segment}){2,}"
  @source_patterns [
    Regex.compile!(~S'\bcapability:\s*"(?<capability>' <> @capability <> ~S')"'),
    Regex.compile!(
      ~S'\b(?:allowed\?|Authz\.(?:can|authorize!|filter_allowed))\s*\([^\n]*?"(?<capability>' <>
        @capability <> ~S')"'
    ),
    Regex.compile!(
      ~S'@(?:[a-z0-9_]*capability[a-z0-9_]*|[a-z0-9_]*_cap)\s+"(?<capability>' <>
        @capability <> ~S')"'
    )
  ]

  setup_all do
    ContributionRegistry.install!()
    :ok
  end

  test "every literal production capability reference is declared" do
    declared = Authz.capabilities() |> MapSet.new()

    offenders =
      (source_references() ++ contribution_references())
      |> Enum.reject(&MapSet.member?(declared, &1.capability))
      |> Enum.uniq_by(&{&1.capability, &1.location})
      |> Enum.sort_by(&{&1.capability, &1.location})

    assert offenders == [], failure_message(offenders, declared)
  end

  test "the source scanner reports supported references with their lines" do
    source = """
    %{capability: "admin.system.session.list"}
    allowed?(scope, "admin.user.list")
    Authz.can(actor, "admin.company.view", resource)
    @manage_cap "admin.audit.log.manage"
    %{id: "admin.system.not-a-capability-reference"}
    """

    assert references_in_source("fixture.ex", source) == [
             %{capability: "admin.system.session.list", location: "fixture.ex:1"},
             %{capability: "admin.user.list", location: "fixture.ex:2"},
             %{capability: "admin.company.view", location: "fixture.ex:3"},
             %{capability: "admin.audit.log.manage", location: "fixture.ex:4"}
           ]
  end

  defp source_references do
    ["apps/*/*/lib/**/*.{ex,heex}", "apps/*/*/priv/**/*.exs"]
    |> Enum.flat_map(&Path.wildcard(Path.join(@workspace_root, &1)))
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      relative = Path.relative_to(path, @workspace_root)
      references_in_source(relative, File.read!(path))
    end)
  end

  defp references_in_source(path, source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      @source_patterns
      |> Enum.flat_map(fn pattern ->
        Regex.scan(pattern, line, capture: :all_names)
        |> Enum.map(fn [capability] ->
          %{capability: capability, location: "#{path}:#{line_number}"}
        end)
      end)
      |> Enum.uniq()
    end)
  end

  defp contribution_references do
    ContributionRegistry.snapshot!().consumers
    |> Enum.flat_map(fn {consumer, contribution} ->
      contribution
      |> referenced_capabilities()
      |> Enum.map(&%{capability: &1, location: "installed #{consumer} contributions"})
    end)
  end

  defp referenced_capabilities(term) when is_map(term) do
    direct =
      term
      |> Map.take([:capability, :capabilities])
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(&CapabilityKey.valid?/1)

    nested =
      term
      |> Map.drop([:capability, :capabilities])
      |> Map.values()
      |> Enum.flat_map(&referenced_capabilities/1)

    direct ++ nested
  end

  defp referenced_capabilities(term) when is_list(term),
    do: Enum.flat_map(term, &referenced_capabilities/1)

  defp referenced_capabilities(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.flat_map(&referenced_capabilities/1)

  defp referenced_capabilities(_term), do: []

  defp failure_message([], _declared), do: ""

  defp failure_message(offenders, declared) do
    details =
      Enum.map_join(offenders, "\n", fn offender ->
        suggestion = closest_capability(offender.capability, declared)

        "  #{offender.location} references #{inspect(offender.capability)}; " <>
          "did you mean #{inspect(suggestion)}?"
      end)

    """
    production code references capabilities that no installed module declares:
    #{details}

    Declare the capability through an Authz contribution or correct the reference.
    Unknown capabilities fail closed at runtime, so leaving one here silently hides
    or denies the feature.
    """
  end

  defp closest_capability(capability, declared) do
    target_segments = capability |> String.split(".") |> MapSet.new()

    Enum.max_by(declared, fn candidate ->
      candidate_segments = candidate |> String.split(".") |> MapSet.new()

      overlap =
        target_segments
        |> MapSet.intersection(candidate_segments)
        |> MapSet.size()

      union_size =
        target_segments
        |> MapSet.union(candidate_segments)
        |> MapSet.size()

      {overlap / union_size, String.jaro_distance(capability, candidate)}
    end)
  end
end
