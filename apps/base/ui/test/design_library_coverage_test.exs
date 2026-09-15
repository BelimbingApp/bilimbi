defmodule Bilimbi.Base.UI.DesignLibraryCoverageTest do
  @moduledoc """
  The screens under `/system/design-library` are the human review surface for
  shared UI. These guards keep that surface truthful about two things: which
  shared components it presents, and how much of each component it presents.

  Both sides are derived. Components and their states come from Phoenix's
  `__components__/0` reflection; what the library shows comes from the parsed
  template (`Bilimbi.Base.UI.DesignLibrarySource`). A component that gains a
  declared state turns the state guard red until the library shows it.

  A component that declares no state at all — today `pagination` and
  `inline_edit`, which vary from their data rather than from an attr — is held
  to presence only. `icon` declares none either, but it branches on the icon
  registry, so the `{:icon, :source}` axis below still holds it to showing both
  a heroicon and a registered icon.

  Appearing in the library is not the same as being complete, and being used
  is not the same as being presented. A component is presented when it has a
  `component-<name>` block of its own that calls it; the library's own chrome
  and the containers that frame some *other* specimen do not count, and they
  contribute no state either.

  These guards are excluded from the default run until the Design Library
  specimens they report are corrected. Run them with
  `mix test --include design_library_drift`.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.Components
  alias Bilimbi.Base.UI.DesignLibrarySource, as: Source
  alias Bilimbi.Base.UI.IconRegistry

  @moduletag :design_library_drift

  setup_all do
    tree = Source.tree()

    assert :components in Enum.map(Source.areas(tree), &elem(&1, 0)),
           floor_failure("has no `if @area == :components do` block")

    assert Source.presented(tree) != [], floor_failure("presents no element at all")

    %{catalog: Source.catalog(tree)}
  end

  test "every public component is presented in the Design Library", %{catalog: catalog} do
    missing = Enum.reject(Source.public_components(), &(Source.entry_calls(&1, catalog) != []))

    assert missing == [],
           """
           These components are public in Bilimbi.Base.UI.Components but the
           Design Library never presents them:

               #{Enum.map_join(missing, ", ", &"<.#{&1}>")}

           A component is presented by a `component-<name>` block of its own,
           inside one of the library's areas (the `if @area == …` blocks of
           #{Path.relative_to_cwd(Source.path())}). Using it to frame another
           specimen, or in the library's own page chrome, is not a presentation
           of it, for the same reason a screen using `<.page>` does not present
           `<.page>`. A component missing from the human review surface is a
           component nobody can validate in context.
           """
  end

  test "every declared state of every public component is presented", %{catalog: catalog} do
    report =
      for name <- Source.public_components(),
          calls = Source.entry_calls(name, catalog),
          {axis, expected} <- axes(name),
          observed = observed(name, axis, calls),
          missing = expected -- observed,
          missing != [] do
        {name, axis, missing, observed, calls}
      end

    assert report == [],
           """
           The Design Library presents these components in fewer states than
           they declare. Every attr with `values:`, every boolean attr with a
           default, every optional `:string` attr, every optional slot and
           every repeating slot is a state a reviewer must be able to see:

           #{Enum.map_join(report, "\n", &describe_gap/1)}

           A state counts only when the template spells it out (a literal attr
           value, a slot that is present or absent). Values computed at render
           time, like `kind={row.kind}`, prove nothing about what is shown.
           """
  end

  # Every guard here passes when it finds nothing wrong, so an empty read is
  # indistinguishable from a complete library. Assert the tree yielded the
  # surface under test before trusting any verdict.
  defp floor_failure(symptom) do
    """
    #{Path.relative_to_cwd(Source.path())} #{symptom}, so these guards would
    report a complete library without reading a single specimen. Either the
    template abandoned the `if @area == …` convention that
    Bilimbi.Base.UI.DesignLibrarySource derives areas from, or that module can
    no longer read the parser's output. Fix the reader before trusting the
    guards.
    """
  end

  ## State axes, derived from the component definition

  # An axis is `{descriptor, expected_values}`. Descriptors:
  #
  #   * `{:attr, name}` — an attr declared with `values:`, or a boolean attr
  #     with a default. An omitted attr presents its declared default.
  #   * `{:attr_presence, name}` — an optional `:string` attr (declared
  #     `default: nil`), presented as `:present`/`:absent`. `<.card title>`
  #     renders a titled header the untitled card does not have.
  #   * `{:slot, name}` — an optional slot, presented as `:present`/`:absent`.
  #   * `{:slot_count, name}` — a required repeating slot such as `<.list>`'s
  #     `:item`, presented as `:one`/`:many`. One row hides how repetition
  #     reads.
  #   * `{:slot_attr, slot, name}` — a slot attr declared with `values:`.
  #   * `{:icon, :source}` — `<.icon>` declares no values, but it branches on
  #     the icon registry (`registered_icon` vs `hero_icon`), and the library
  #     has to show both sides of that branch.
  defp axes(name) do
    %{attrs: attrs, slots: slots} = Components.__components__()[name]

    attr_axes =
      for %{name: attr, type: type, opts: opts} <- attrs,
          expected = attr_values(type, opts),
          expected != nil,
          do: {{:attr, attr}, expected}

    presence_axes =
      for %{name: attr, type: :string, opts: opts} <- attrs,
          attr != :id,
          Keyword.get(opts, :default, :none) == nil,
          do: {{:attr_presence, attr}, [:present, :absent]}

    slot_axes =
      for %{name: slot, required: false} <- slots,
          do: {{:slot, slot}, [:present, :absent]}

    # Phoenix renders every named slot as a list; a required one is the
    # component's repeating unit. `:inner_block` is the body, not a repetition.
    count_axes =
      for %{name: slot, required: true} <- slots,
          slot != :inner_block,
          do: {{:slot_count, slot}, [:one, :many]}

    slot_attr_axes =
      for %{name: slot, attrs: slot_attrs} <- slots,
          %{name: attr, type: type, opts: opts} <- slot_attrs,
          expected = attr_values(type, opts),
          expected != nil,
          do: {{:slot_attr, slot, attr}, expected}

    attr_axes ++ presence_axes ++ slot_axes ++ count_axes ++ slot_attr_axes ++ extra_axes(name)
  end

  defp attr_values(:boolean, opts) do
    if Keyword.has_key?(opts, :default), do: [true, false]
  end

  # Only declared values are states. Phoenix does not let an attr declare an
  # absent value as its default alongside `values:`, so what `<.button>` with
  # no `variant` renders is an implementation detail, not a declared state.
  defp attr_values(_type, opts), do: Keyword.get(opts, :values)

  defp extra_axes(:icon), do: [{{:icon, :source}, [:hero, :registry]}]

  defp extra_axes(_name), do: []

  ## What the calls present

  defp observed(name, axis, calls) do
    calls
    |> Enum.flat_map(&present(name, axis, &1))
    |> Enum.reject(&(&1 == :dynamic))
    |> Enum.uniq()
  end

  defp present(name, {:attr, attr}, call) do
    [attr_state(Source.attr(call, Atom.to_string(attr)), default_for(name, attr))]
  end

  # A value computed at render time can still be nil, so it proves neither
  # presence nor absence.
  defp present(_name, {:attr_presence, attr}, call) do
    case Source.attr(call, Atom.to_string(attr)) do
      nil -> [:absent]
      {:literal, _value} -> [:present]
      {:dynamic, _code} -> [:dynamic]
    end
  end

  defp present(_name, {:slot, slot}, call) do
    given? =
      if slot == :inner_block,
        do: Source.inner_block?(call),
        else: Source.slots(call, Atom.to_string(slot)) != []

    [if(given?, do: :present, else: :absent)]
  end

  defp present(_name, {:slot_count, slot}, call) do
    case Source.slots(call, Atom.to_string(slot)) do
      [] -> []
      [_one] -> [:one]
      _many -> [:many]
    end
  end

  defp present(name, {:slot_attr, slot, attr}, call) do
    default = slot_attr_default(name, slot, attr)

    for slot_call <- Source.slots(call, Atom.to_string(slot)),
        do: attr_state(Source.attr(slot_call, Atom.to_string(attr)), default)
  end

  defp present(:icon, {:icon, axis}, call) do
    case Source.attr(call, "name") do
      {:literal, icon} when is_binary(icon) -> [icon_state(axis, icon)]
      _ -> [:dynamic]
    end
  end

  defp attr_state(nil, default), do: default
  defp attr_state({:literal, value}, _default), do: value
  defp attr_state({:dynamic, _code}, _default), do: :dynamic

  defp icon_state(:source, icon) do
    case IconRegistry.fetch(icon) do
      {:ok, _} -> :registry
      :error -> :hero
    end
  end

  defp default_for(name, attr) do
    %{opts: opts} = Enum.find(Components.__components__()[name].attrs, &(&1.name == attr))
    default_state(opts)
  end

  defp slot_attr_default(name, slot, attr) do
    %{attrs: attrs} = Enum.find(Components.__components__()[name].slots, &(&1.name == slot))
    %{opts: opts} = Enum.find(attrs, &(&1.name == attr))
    default_state(opts)
  end

  # An omitted attr presents the declared default. Without one it presents
  # nothing this guard can name, which never satisfies a declared value.
  defp default_state(opts) do
    case Keyword.fetch(opts, :default) do
      {:ok, default} -> default
      :error -> :absent
    end
  end

  ## Failure copy

  defp describe_gap({name, axis, missing, observed, calls}) do
    lines =
      case calls do
        [] -> "no `component-*` block of its own calls it"
        calls -> "called at line " <> Enum.map_join(calls, ", ", &to_string(&1.line))
      end

    """
      <.#{name}> #{describe_axis(axis)}
        missing: #{Enum.map_join(missing, ", ", &inspect/1)}
        shown:   #{if observed == [], do: "nothing", else: Enum.map_join(observed, ", ", &inspect/1)}
        #{lines}
    """
  end

  defp describe_axis({:attr, attr}), do: "attr `#{attr}`"
  defp describe_axis({:attr_presence, attr}), do: "optional attr `#{attr}` (given or omitted)"
  defp describe_axis({:slot, slot}), do: "slot `<:#{slot}>`"
  defp describe_axis({:slot_count, slot}), do: "slot `<:#{slot}>` (one or many)"
  defp describe_axis({:slot_attr, slot, attr}), do: "slot attr `<:#{slot} #{attr}>`"
  defp describe_axis({:icon, :source}), do: "source (heroicon or icon registry)"
end
