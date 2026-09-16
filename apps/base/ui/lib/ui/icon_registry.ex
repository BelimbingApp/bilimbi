defmodule Bilimbi.Base.UI.IconRegistry do
  @moduledoc """
  Product glyphs and the named action vocabulary rendered through `<.icon>`.

  Custom SVGs cover glyphs Heroicons does not provide. Action names map each
  familiar user-facing meaning onto one Heroicon so call sites name the action
  rather than a raw `hero-*` string. `<.icon>` still passes unknown names
  beginning with `hero-` through to generated Heroicons.

  A small set of call sites spell an action with its literal `bilimbi-*`
  Heroicon name (`bilimbi-plus`, `bilimbi-pencil`, `bilimbi-link-slash`,
  `bilimbi-x-mark`) instead of the semantic name (`create`, `edit`, `unlink`,
  `close`). Both resolve to the same Heroicon; the `bilimbi-*` spellings are
  registered as-is rather than rewritten across call sites.

  `lookup/1` raises for any other name that is neither registered here nor a
  `hero-*` passthrough, instead of silently rendering a generic fallback
  glyph. Every name actually used by a call site must resolve to something
  meaningful; use a raw `hero-*` name to reach an icon this module does not
  name.

  Logout is intentionally absent: Bilimbi keeps `hero-arrow-right-on-rectangle`.
  Destination navigation has no single action glyph; menu contributions keep
  their own icons.

  `shell/1` is the other half of the registry: it names the accepted icon
  meaning for each shell action, so the top bar, the account menu and Design
  Library cannot drift apart on the same action. Its values are ordinary
  `hero-*` names and need no `@icons` entry.
  """

  @type icon :: %{
          view_box: String.t(),
          fill: String.t(),
          paths: [String.t()]
        }

  @icons %{
    "bilimbi-pin" => %{
      view_box: "0 0 24 24",
      fill: "none",
      paths: [
        "M16.114 1.553l6.333 6.333a1.75 1.75 0 0 1-.603 2.869l-1.63.633a5.67 5.67 0 0 0-3.395 3.725l-1.131 3.959a1.75 1.75 0 0 1-2.92.757L9 16.061 7.939 15l-3.768-3.768a1.75 1.75 0 0 1 .757-2.92l3.959-1.131a5.666 5.666 0 0 0 3.725-3.395l.633-1.63a1.75 1.75 0 0 1 2.869-.603Z",
        "M9 16.061L3.405 21.655"
      ]
    },
    "bilimbi-impersonate" => %{
      view_box: "0 0 24 24",
      fill: "none",
      paths: [
        "M21 15.75A2.25 2.25 0 0 1 18.75 18H5.25A2.25 2.25 0 0 1 3 15.75V5.25A2.25 2.25 0 0 1 5.25 3h13.5A2.25 2.25 0 0 1 21 5.25v10.5Z",
        "M10.5 18v3.25h-2.25a.75.75 0 0 0 0 1.5h7.5a.75.75 0 0 0 0-1.5h-2.25V18",
        "M12 6.75a2.75 2.75 0 1 1 0 5.5 2.75 2.75 0 0 1 0-5.5Z",
        "M6 17a7.5 7.5 0 0 1 12 0"
      ]
    },
    "hero-impersonate" => %{
      view_box: "0 0 24 24",
      fill: "none",
      paths: [
        "M21 15.75A2.25 2.25 0 0 1 18.75 18H5.25A2.25 2.25 0 0 1 3 15.75V5.25A2.25 2.25 0 0 1 5.25 3h13.5A2.25 2.25 0 0 1 21 5.25v10.5Z",
        "M10.5 18v3.25h-2.25a.75.75 0 0 0 0 1.5h7.5a.75.75 0 0 0 0-1.5h-2.25V18",
        "M12 6.75a2.75 2.75 0 1 1 0 5.5 2.75 2.75 0 0 1 0-5.5Z",
        "M6 17a7.5 7.5 0 0 1 12 0"
      ]
    }
  }

  @shell %{
    clock: "hero-clock",
    light: "hero-sun",
    dark: "hero-moon",
    system: "hero-computer-desktop",
    navigation: "hero-bars-3",
    chevron: "hero-chevron-down-mini",
    password: "hero-key",
    logout: "hero-arrow-right-on-rectangle",
    warning: "hero-exclamation-triangle"
  }

  @doc "Accepted shell icon meanings; logout preserves Bilimbi's own treatment."
  def shell(action), do: Map.fetch!(@shell, action)

  # One chosen Heroicon per familiar action meaning. Theme and sort keep a
  # name per state because those controls are the meaning, not one glyph.
  @actions %{
    "create" => "hero-plus",
    "edit" => "hero-pencil",
    "delete" => "hero-trash",
    "view" => "hero-eye",
    "filter" => "hero-funnel",
    "search" => "hero-magnifying-glass",
    "sort" => "hero-chevron-up-down",
    "sort-asc" => "hero-chevron-up",
    "sort-desc" => "hero-chevron-down",
    "export" => "hero-arrow-down-tray",
    "import" => "hero-inbox-arrow-down",
    "refresh" => "hero-arrow-path",
    "notify" => "hero-bell",
    "expand" => "hero-chevron-right",
    "collapse" => "hero-chevron-down",
    "close" => "hero-x-mark",
    "settings" => "hero-cog-6-tooth",
    "theme-light" => "hero-sun",
    "theme-dark" => "hero-moon",
    "theme-system" => "hero-computer-desktop",
    "clock" => "hero-clock",
    "sidebar" => "hero-bars-3",
    "save" => "hero-check-circle",
    "confirm" => "hero-check",
    "back" => "hero-arrow-left",
    "forward" => "hero-arrow-right",
    "page-previous" => "hero-chevron-left",
    "page-next" => "hero-chevron-right",
    "external" => "hero-arrow-top-right-on-square",
    "link" => "hero-link",
    "unlink" => "hero-link-slash",
    "archive" => "hero-archive-box",
    "unarchive" => "hero-archive-box-x-mark",
    "copy" => "hero-clipboard",
    "attach" => "hero-paper-clip",
    "share" => "hero-share",
    "help" => "hero-question-mark-circle",
    "information" => "hero-information-circle",
    "success" => "hero-check-circle",
    "warning" => "hero-exclamation-triangle",
    "error" => "hero-exclamation-circle",
    "play" => "hero-play",
    "pause" => "hero-pause",
    "stop" => "hero-stop",
    "fullscreen" => "hero-arrows-pointing-out",
    "fullscreen-exit" => "hero-arrows-pointing-in",
    "inspect" => "hero-document-magnifying-glass",
    "dashboard" => "hero-squares-2x2",
    "status" => "hero-signal",

    # Literal `bilimbi-*` spellings of the four actions above, kept for the
    # call sites that already name the Heroicon directly. Each resolves to
    # the exact same glyph as its semantic sibling; prefer the semantic name
    # ("create", "edit", "unlink", "close") at a new call site.
    "bilimbi-plus" => "hero-plus",
    "bilimbi-pencil" => "hero-pencil",
    "bilimbi-link-slash" => "hero-link-slash",
    "bilimbi-x-mark" => "hero-x-mark"
  }

  @spec fetch(String.t()) :: {:ok, icon()} | :error
  def fetch(name) when is_binary(name), do: Map.fetch(@icons, name)
  def fetch(_name), do: :error

  @spec action(String.t()) :: {:ok, String.t()} | :error
  def action(name) when is_binary(name), do: Map.fetch(@actions, name)
  def action(_name), do: :error

  @doc """
  Resolves a name to a registered custom SVG or a chosen Heroicon.

  A `hero-*` name with no registry entry returns `:error` so `<.icon>` can
  pass it straight through to generated Heroicons. Any other unregistered
  name raises: a fail-soft registry is how a typo or an unregistered
  `bilimbi-*`/action name used to render the same meaningless fallback glyph
  for every caller without anyone noticing. Register the name in `@icons` or
  `@actions` (or use a raw `hero-*` name) instead of relying on the fallback.
  """
  @spec lookup(String.t()) :: {:svg, icon()} | {:hero, String.t()} | :error
  def lookup(name) when is_binary(name) do
    case Map.fetch(@icons, name) do
      {:ok, icon} ->
        {:svg, icon}

      :error ->
        case Map.fetch(@actions, name) do
          {:ok, hero_name} -> {:hero, hero_name}
          :error -> unregistered(name)
        end
    end
  end

  def lookup(_name), do: :error

  defp unregistered("hero-" <> _), do: :error

  defp unregistered(name) do
    raise ArgumentError, """
    Bilimbi.Base.UI.IconRegistry has no icon named #{inspect(name)}.

    Register it in the @icons or @actions map in \
    apps/base/ui/lib/ui/icon_registry.ex, or use a raw "hero-*" Heroicon \
    name if no semantic action name applies.
    """
  end

  @spec actions() :: %{String.t() => String.t()}
  def actions, do: @actions
end
