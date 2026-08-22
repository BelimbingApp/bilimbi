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

  # The light values `@theme` takes from the Tailwind scale, resolved to hex
  # so the ratios are computable. If Tailwind's palette shifts under an
  # upgrade, this table fails loudly instead of silently gating on air.
  @tailwind %{
    "var(--color-white)" => "#ffffff",
    "var(--color-stone-50)" => "#fafaf9",
    "var(--color-stone-100)" => "#f5f5f4",
    "var(--color-stone-200)" => "#e7e5e4",
    "var(--color-stone-300)" => "#d6d3d1",
    "var(--color-stone-400)" => "#a8a29e",
    "var(--color-stone-500)" => "#79716b",
    "var(--color-stone-600)" => "#57534e",
    "var(--color-stone-900)" => "#1c1917",
    "var(--color-stone-950)" => "#0c0a09",
    "var(--color-lime-600)" => "#84cc16",
    "var(--color-lime-950)" => "#1a2e05",
    "var(--color-emerald-50)" => "#ecfdf5",
    "var(--color-emerald-600)" => "#059669",
    "var(--color-emerald-900)" => "#064e3b",
    "var(--color-amber-50)" => "#fffbeb",
    "var(--color-amber-900)" => "#78350f",
    "var(--color-red-50)" => "#fef2f2",
    "var(--color-red-600)" => "#dc2626",
    "var(--color-red-900)" => "#7f1d1d"
  }

  # {foreground, background, minimum ratio}. Body text pairs at 4.5; the
  # action button label and badge chips are bold/large-adjacent at 3.0.
  @pairs [
    {"ink", "surface", 4.5},
    {"ink", "canvas", 4.5},
    {"ink-muted", "surface", 4.5},
    {"action-ink", "action", 4.5},
    {"success-ink", "success-surface", 4.5},
    {"warning-ink", "warning-surface", 4.5},
    {"danger-ink", "danger-surface", 4.5},
    {"brand-ink", "brand-surface", 4.5}
  ]

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
        Map.get(@tailwind, reference) ||
          case Regex.run(~r/var\(--color-([a-z0-9-]+)\)/, reference) do
            [_, referenced_role] when is_map_key(tokens, referenced_role) ->
              resolve!(tokens, referenced_role)

            _ ->
              flunk("no hex known for #{reference} — extend the @tailwind table")
          end
    end
  end

  defp contrast(hex_a, hex_b) do
    {la, lb} = {luminance(hex_a), luminance(hex_b)}
    (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  end

  defp luminance("#" <> hex) do
    [r, g, b] =
      hex
      |> String.to_charlist()
      |> Enum.chunk_every(2)
      |> Enum.map(fn pair -> pair |> List.to_string() |> String.to_integer(16) end)
      |> Enum.map(fn channel ->
        channel = channel / 255

        if channel <= 0.04045,
          do: channel / 12.92,
          else: :math.pow((channel + 0.055) / 1.055, 2.4)
      end)

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end
end
