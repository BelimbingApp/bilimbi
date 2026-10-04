defmodule Bilimbi.Base.UI.Components.Icon do
  @moduledoc """
  The icon component, the leaf every other component group draws from.

  `use Bilimbi.Base.UI.Components` imports it with the rest.
  """
  use Phoenix.Component

  alias Bilimbi.Base.UI.IconRegistry

  @doc """
  Renders a named action icon or a [Heroicon](https://heroicons.com).

  Prefer a name from `Bilimbi.Base.UI.IconRegistry` so the action meaning is
  explicit. Unknown names beginning with `hero-` still pass through to
  generated Heroicons. Custom product glyphs such as `bilimbi-pin` render as
  inline SVG. A name that is neither registered nor `hero-`-prefixed raises
  `ArgumentError` rather than rendering a meaningless fallback glyph; pass a
  name that came from stored data through `IconRegistry.renderable?/1` first.

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="close" />
      <.icon name="refresh" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr(:name, :string, required: true)
  attr(:class, :any, default: "size-4")

  def icon(assigns) do
    case IconRegistry.lookup(assigns.name) do
      {:svg, icon} -> registered_icon(assign(assigns, :icon, icon))
      {:hero, hero_name} -> hero_icon(assign(assigns, :name, hero_name))
      :error -> hero_icon(assigns)
    end
  end

  defp registered_icon(assigns) do
    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      viewBox={@icon.view_box}
      fill={@icon.fill}
      stroke={@icon.fill == "none" && "currentColor"}
      stroke-width={@icon.fill == "none" && "1.5"}
      aria-hidden="true"
    >
      <path
        :for={path <- @icon.paths}
        stroke-linecap="round"
        stroke-linejoin="round"
        d={path}
      />
    </svg>
    """
  end

  defp hero_icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  defp hero_icon(assigns), do: hero_icon(assign(assigns, :name, "hero-square-3-stack-3d"))
end
