defmodule BilimbiWeb.ThemeContrastTest do
  @moduledoc """
  Contrast gates for the color themes (#657): the steward's palette review
  requires the capture-verified pairs asserted programmatically, and the two
  hand-duplicated dark blocks in `app.css` must never drift apart.

  Ratios follow WCAG 2 relative luminance. Body-text pairs must reach 4.5:1;
  large/bold text and status-badge pairs must reach 3:1.
  """

  use ExUnit.Case, async: true

  @css_path Path.expand("../assets/css/app.css", __DIR__)

  # Tailwind 4.3 palette values used by the semantic roles, resolved to sRGB
  # hex so the ratios are computable. If Tailwind's palette shifts under an
  # upgrade, this table must move with the reviewed palette change.
  @tailwind %{
    "var(--color-white)" => "#ffffff",
    "var(--color-stone-50)" => "#fafaf9",
    "var(--color-stone-100)" => "#f5f5f4",
    "var(--color-stone-200)" => "#e7e5e4",
    "var(--color-stone-300)" => "#d6d3d1",
    "var(--color-stone-400)" => "#a6a09b",
    "var(--color-stone-500)" => "#79716b",
    "var(--color-stone-600)" => "#57534d",
    "var(--color-stone-700)" => "#44403b",
    "var(--color-stone-800)" => "#292524",
    "var(--color-stone-900)" => "#1c1917",
    "var(--color-stone-950)" => "#0c0a09",
    "var(--color-lime-50)" => "#f7fee7",
    "var(--color-lime-100)" => "#ecfcca",
    "var(--color-lime-300)" => "#bbf451",
    "var(--color-lime-400)" => "#9ae600",
    "var(--color-lime-500)" => "#7ccf00",
    "var(--color-lime-600)" => "#5ea500",
    "var(--color-lime-700)" => "#497d00",
    "var(--color-lime-800)" => "#3c6300",
    "var(--color-lime-950)" => "#192e03",
    "var(--color-yellow-100)" => "#fef9c2",
    "var(--color-emerald-50)" => "#ecfdf5",
    "var(--color-emerald-200)" => "#a4f4cf",
    "var(--color-emerald-500)" => "#00bc7d",
    "var(--color-emerald-600)" => "#009966",
    "var(--color-emerald-800)" => "#006045",
    "var(--color-emerald-900)" => "#004f3b",
    "var(--color-emerald-950)" => "#002c22",
    "var(--color-amber-50)" => "#fffbeb",
    "var(--color-amber-200)" => "#fee685",
    "var(--color-amber-400)" => "#ffb900",
    "var(--color-amber-500)" => "#fe9a00",
    "var(--color-amber-700)" => "#bb4d00",
    "var(--color-amber-900)" => "#7b3306",
    "var(--color-amber-950)" => "#461901",
    "var(--color-red-50)" => "#fef2f2",
    "var(--color-red-200)" => "#ffc9c9",
    "var(--color-red-400)" => "#ff6467",
    "var(--color-red-500)" => "#fb2c36",
    "var(--color-red-600)" => "#e7000b",
    "var(--color-red-700)" => "#c10007",
    "var(--color-red-800)" => "#9f0712",
    "var(--color-red-900)" => "#82181a",
    "var(--color-red-950)" => "#460809"
  }

  # {foreground, background, minimum ratio}. Body text pairs at 4.5; the
  # action button label and badge chips are bold/large-adjacent at 3.0.
  @pairs [
    {"ink", "surface", 4.5},
    {"ink", "canvas", 4.5},
    {"ink-muted", "surface", 4.5},
    {"link", "surface-sidebar", 4.5},
    {"muted", "surface-sidebar", 4.5},
    {"action-ink", "action", 4.5},
    {"success-ink", "success-surface", 4.5},
    {"warning-ink", "warning-surface", 4.5},
    {"danger-ink", "danger-surface", 4.5},
    {"brand-ink", "brand-surface", 4.5}
  ]

  @surface_roles ~w(canvas surface surface-sunken surface-muted surface-sidebar)
  @dark_surface_ladder ~w(canvas surface-sidebar surface surface-sunken surface-muted)
  @line_roles ~w(high-contrast-line line low-contrast-line)

  test "light and dark palettes meet the contrast gates" do
    css = File.read!(@css_path)
    light = tokens_in(theme_block(css))
    [dark_media, dark_attr] = dark_blocks(css)

    assert dark_media == dark_attr,
           "the media-guarded and attribute-guarded dark blocks drifted apart"

    for {fg, bg, minimum} <- @pairs, {name, tokens} <- [{"light", light}, {"dark", dark_media}] do
      fg_hex = resolve!(tokens, fg)
      bg_hex = resolve!(tokens, bg)
      ratio = contrast(fg_hex, bg_hex)

      assert ratio >= minimum,
             "#{name}: #{fg} (#{fg_hex}) on #{bg} (#{bg_hex}) is #{Float.round(ratio, 2)}:1, " <>
               "below #{minimum}:1"
    end
  end

  test "neutral line contrast remains ordered on every surface" do
    css = File.read!(@css_path)
    light = tokens_in(theme_block(css))
    [dark_media, dark_attr] = dark_blocks(css)

    assert dark_media == dark_attr,
           "the media-guarded and attribute-guarded dark blocks drifted apart"

    for {name, tokens} <- [{"light", light}, {"dark", dark_media}],
        surface_role <- @surface_roles do
      surface_hex = resolve!(tokens, surface_role)

      [high, standard, low] =
        Enum.map(@line_roles, fn line_role ->
          tokens
          |> resolve_line_on_surface!(line_role, surface_hex)
          |> contrast(surface_hex)
        end)

      assert high > standard and standard > low,
             "#{name}: line contrast on #{surface_role} is not high > standard > low: " <>
               "#{Float.round(high, 3)}, #{Float.round(standard, 3)}, #{Float.round(low, 3)}"
    end
  end

  test "link and muted text remain distinct in both themes" do
    css = File.read!(@css_path)
    light = tokens_in(theme_block(css))
    [dark_media, _dark_attr] = dark_blocks(css)

    for {name, tokens} <- [{"light", light}, {"dark", dark_media}] do
      refute resolve!(tokens, "link") == resolve!(tokens, "muted"),
             "#{name}: link and muted text resolve to the same colour"
    end
  end

  test "primary action brightens on hover in both themes" do
    css = File.read!(@css_path)
    light = tokens_in(theme_block(css))
    [dark_media, _dark_attr] = dark_blocks(css)

    for {name, tokens} <- [{"light", light}, {"dark", dark_media}] do
      action = resolve!(tokens, "action")
      hover = resolve!(tokens, "action-hover")

      refute action == hover, "#{name}: primary action and hover resolve to the same colour"

      assert luminance(hover) > luminance(action),
             "#{name}: primary action does not brighten on hover"
    end
  end

  test "dark surfaces retain separate depth" do
    css = File.read!(@css_path)
    [dark_media, _dark_attr] = dark_blocks(css)

    luminances = Enum.map(@dark_surface_ladder, &luminance(resolve!(dark_media, &1)))

    assert Enum.uniq(luminances) == luminances
    assert Enum.chunk_every(luminances, 2, 1, :discard) |> Enum.all?(fn [a, b] -> a < b end)
  end

  defp theme_block(css) do
    [_before, rest] = String.split(css, "@theme {", parts: 2)
    [block, _after] = String.split(rest, "\n}", parts: 2)
    block
  end

  defp dark_blocks(css) do
    Regex.scan(~r/\{\n((?:\s*--color-[a-z-]+:[^;]+;\n)+)\s*\}/, css)
    |> Enum.map(fn [_, block] -> tokens_in(block) end)
    # The first var block is @theme's light set; the last two are the dark pair.
    |> Enum.take(-2)
  end

  defp tokens_in(block) do
    Regex.scan(~r/--color-([a-z-]+):\s*([^;]+);/, block)
    |> Map.new(fn [_, role, value] -> {role, String.trim(value)} end)
  end

  defp resolve!(tokens, role) do
    case Map.fetch!(tokens, role) do
      "#" <> _ = hex ->
        hex

      "var(" <> _ = reference ->
        case Regex.run(~r/var\(--color-([a-z0-9-]+)\)/, reference) do
          [_, referenced_role] -> resolve_reference!(tokens, referenced_role)
          _ -> flunk("invalid colour reference #{reference}")
        end

      "color-mix(" <> _ = mix ->
        case Regex.run(
               ~r/color-mix\(in srgb, var\(--color-([a-z0-9-]+)\) ([0-9]+)%, var\(--color-([a-z0-9-]+)\)\)/,
               mix
             ) do
          [_, first_role, amount, second_role] ->
            mix_over(
              resolve_reference!(tokens, first_role),
              resolve_reference!(tokens, second_role),
              String.to_integer(amount) / 100
            )

          _ ->
            flunk("unsupported colour mix #{mix}")
        end
    end
  end

  defp resolve_reference!(tokens, role) do
    Map.get(@tailwind, "var(--color-#{role})") ||
      if is_map_key(tokens, role),
        do: resolve!(tokens, role),
        else: flunk("no hex known for var(--color-#{role}) — extend the @tailwind table")
  end

  defp resolve_line_on_surface!(tokens, role, surface_hex) do
    value = Map.fetch!(tokens, role)

    case Regex.run(
           ~r/color-mix\(in srgb, var\(--color-([a-z0-9-]+)\) ([0-9]+)%, transparent\)/,
           value
         ) do
      [_, ink_role, amount] ->
        tokens
        |> resolve!(ink_role)
        |> mix_over(surface_hex, String.to_integer(amount) / 100)

      _ ->
        flunk("#{role} must derive from a semantic color over a transparent background")
    end
  end

  defp mix_over(foreground_hex, background_hex, amount) do
    foreground = hex_channels(foreground_hex)
    background = hex_channels(background_hex)

    channels =
      Enum.zip_with(foreground, background, fn foreground_channel, background_channel ->
        round(foreground_channel * amount + background_channel * (1 - amount))
        |> Integer.to_string(16)
        |> String.pad_leading(2, "0")
      end)

    "#" <> Enum.join(channels)
  end

  defp hex_channels("#" <> hex) do
    hex
    |> String.to_charlist()
    |> Enum.chunk_every(2)
    |> Enum.map(fn pair -> pair |> List.to_string() |> String.to_integer(16) end)
  end

  defp contrast(hex_a, hex_b) do
    {la, lb} = {luminance(hex_a), luminance(hex_b)}
    (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  end

  defp luminance("#" <> hex) do
    [r, g, b] =
      hex_channels("#" <> hex)
      |> Enum.map(fn channel ->
        channel = channel / 255

        if channel <= 0.04045,
          do: channel / 12.92,
          else: :math.pow((channel + 0.055) / 1.055, 2.4)
      end)

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end
end
