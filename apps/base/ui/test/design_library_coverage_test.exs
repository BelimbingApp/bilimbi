defmodule Bilimbi.Base.UI.DesignLibraryCoverageTest do
  @moduledoc """
  The screens under `/system/design-library` are the human review surface for
  shared UI. These guards keep that surface truthful about two things: which
  shared components it presents, and how much of each component it presents.

  Both sides are derived. Components and their states come from Phoenix's
  `__components__/0` reflection; what the library shows comes from the parsed
  template (`Bilimbi.Base.UI.DesignLibrarySource`). Neither is a fixture list
  that can drift on its own, and a component that gains a declared state turns
  the state guard red until the library shows it.

  Appearing in the library is not the same as being complete. The library's
  own chrome (its page container, header and sidebar menu) uses shared
  components too, and none of that counts as presenting them.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.Components
  alias Bilimbi.Base.UI.DesignLibrarySource, as: Source
  alias Bilimbi.Base.UI.IconRegistry

  @heroicons_plugin Path.expand("../../../web/assets/vendor/heroicons.js", __DIR__)

  setup_all do
    %{presented: Source.presented()}
  end

  test "every public component is presented in the Design Library", %{presented: presented} do
    missing =
      public_components()
      |> Enum.reject(&(Source.calls(&1, presented) != []))
      |> Enum.sort()

    assert missing == [],
           """
           These components are public in Bilimbi.Base.UI.Components but the
           Design Library never presents them:

               #{Enum.map_join(missing, ", ", &"<.#{&1}>")}

           A call only counts inside one of the library's areas (the
           `if @area == …` blocks of #{Path.relative_to_cwd(Source.path())}),
           outside the sidebar menu. The library's own page chrome using a
           component is not a presentation of it. A component missing from the
           human review surface is a component nobody can validate in context.
           """
  end

  test "every declared state of every public component is presented", %{presented: presented} do
    report =
      for name <- public_components(),
          axes = axes(name),
          axes != [],
          calls = Source.calls(name, presented),
          {axis, expected} <- axes,
          observed = observed(name, axis, calls),
          missing = expected -- observed,
          missing != [] do
        {name, axis, missing, observed, calls}
      end

    assert report == [],
           """
           The Design Library presents these components in fewer states than
           they declare. Every attr with `values:`, every boolean attr with a
           default, every optional slot, and the icon styles the Tailwind plugin
           generates are states a reviewer must be able to see:

           #{Enum.map_join(report, "\n", &describe_gap/1)}

           A state counts only when the template spells it out (a literal attr
           value, a slot that is present or absent). Values computed at render
           time, like `kind={row.kind}`, prove nothing about what is shown.
           """
  end

  # `__components__/0` also reports internals — `error/1` and
  # `table_sort_heading/1` are called only by other components and have no
  # business on the Design Library page. Public means callable from another
  # module.
  defp public_components do
    Components.__components__()
    |> Map.keys()
    |> Enum.filter(&function_exported?(Components, &1, 1))
    |> Enum.sort()
  end

  ## State axes, derived from the component definition

  # An axis is `{descriptor, expected_values}`. Descriptors:
  #
  #   * `{:attr, name}` — an attr declared with `values:`, or a boolean attr
  #     with a default. An omitted attr presents its declared default.
  #   * `{:slot, name}` — an optional slot, presented as `:present`/`:absent`.
  #   * `{:slot_attr, slot, name}` — a slot attr declared with `values:`.
  #   * `{:icon, :style}` / `{:icon, :source}` — `<.icon>` has no declared
  #     values, but the Tailwind plugin enumerates the heroicon styles it
  #     builds and the component branches on the icon registry. Both are read
  #     from their sources, so a new style or registry entry changes the
  #     expectation here.
  defp axes(name) do
    %{attrs: attrs, slots: slots} = Components.__components__()[name]

    attr_axes =
      for %{name: attr, type: type, opts: opts} <- attrs,
          expected = attr_values(type, opts),
          expected != nil,
          do: {{:attr, attr}, expected}

    slot_axes =
      for %{name: slot, required: false} <- slots,
          do: {{:slot, slot}, [:present, :absent]}

    slot_attr_axes =
      for %{name: slot, attrs: slot_attrs} <- slots,
          %{name: attr, type: type, opts: opts} <- slot_attrs,
          expected = attr_values(type, opts),
          expected != nil,
          do: {{:slot_attr, slot, attr}, expected}

    attr_axes ++ slot_axes ++ slot_attr_axes ++ extra_axes(name)
  end

  defp attr_values(:boolean, opts) do
    if Keyword.has_key?(opts, :default), do: [true, false]
  end

  # Only declared values are states. Phoenix does not let an attr declare an
  # absent value as its default alongside `values:`, so what `<.button>` with
  # no `variant` renders is an implementation detail, not a declared state.
  defp attr_values(_type, opts), do: Keyword.get(opts, :values)

  defp extra_axes(:icon) do
    [{{:icon, :style}, hero_styles()}, {{:icon, :source}, [:hero, :registry]}]
  end

  defp extra_axes(_name), do: []

  # apps/web/assets/vendor/heroicons.js builds one class family per style:
  #
  #     ["", "/24/outline"], ["-solid", "/24/solid"], …
  #
  # The suffix list is the definition of which `hero-*` names exist.
  defp hero_styles do
    source = File.read!(@heroicons_plugin)

    styles =
      for [_, suffix] <- Regex.scan(~r/\[\s*"(-?[a-z]*)"\s*,\s*"\/\d+\/[a-z]+"\s*\]/, source),
          do: style_from_suffix(suffix)

    assert styles != [],
           "could not read the heroicon style list from #{@heroicons_plugin}"

    styles
  end

  defp style_from_suffix(""), do: :outline
  defp style_from_suffix("-" <> style), do: String.to_atom(style)

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

  defp present(_name, {:slot, slot}, call) do
    given? =
      if slot == :inner_block,
        do: Source.inner_block?(call),
        else: Source.slots(call, Atom.to_string(slot)) != []

    [if(given?, do: :present, else: :absent)]
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

  defp icon_state(:style, icon) do
    case IconRegistry.fetch(icon) do
      {:ok, _} ->
        :dynamic

      :error ->
        hero_styles()
        |> Enum.reject(&(&1 == :outline))
        |> Enum.find(:outline, &String.ends_with?(icon, "-#{&1}"))
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
        [] -> "never called inside an area"
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
  defp describe_axis({:slot, slot}), do: "slot `<:#{slot}>`"
  defp describe_axis({:slot_attr, slot, attr}), do: "slot attr `<:#{slot} #{attr}>`"
  defp describe_axis({:icon, :style}), do: "heroicon style (name suffix)"
  defp describe_axis({:icon, :source}), do: "source (heroicon or icon registry)"
end
