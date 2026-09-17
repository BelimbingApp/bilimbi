defmodule BilimbiWeb.ThemeMotionTest do
  @moduledoc """
  Reduced-motion gate (parity finding M1): one global rule in `app.css` must
  suppress transitions and animations for everyone whose operating system asks
  for reduced motion, so no component needs its own opt-out.
  """

  use ExUnit.Case, async: true

  @css_path Path.expand("../assets/css/app.css", __DIR__)

  test "a top-level reduced-motion rule collapses every transition and animation" do
    css = File.read!(@css_path)

    # Top level: the rule starts at column 0, so it is not nested inside a
    # viewport query the way the earlier drawer-only guard was.
    assert [[_, body]] =
             Regex.scan(
               ~r/^@media \(prefers-reduced-motion: reduce\) \{\n(.*?)\n\}/ms,
               css
             ),
           "expected exactly one top-level prefers-reduced-motion block"

    assert body =~ ~r/^\s*\*,\s*\n\s*::before,\s*\n\s*::after\s*\{/m,
           "the rule must apply to every element and pseudo-element"

    for declaration <- [
          ~r/animation-duration:\s*0\.01ms !important;/,
          ~r/animation-iteration-count:\s*1 !important;/,
          ~r/transition-duration:\s*0\.01ms !important;/,
          ~r/scroll-behavior:\s*auto !important;/
        ] do
      assert body =~ declaration, "reduced-motion block is missing #{inspect(declaration)}"
    end
  end
end
