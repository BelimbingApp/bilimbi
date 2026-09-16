defmodule Bilimbi.Base.UI.IconRegistryTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  alias Bilimbi.Base.UI.IconRegistry

  test "provides the product pin when Heroicons has no matching glyph" do
    assert {:ok, icon} = IconRegistry.fetch("bilimbi-pin")
    assert icon.view_box == "0 0 24 24"
    assert icon.fill == "none"
    assert length(icon.paths) == 2
    assert {:svg, ^icon} = IconRegistry.lookup("bilimbi-pin")
  end

  test "provides the product impersonate icon" do
    assert {:ok, icon} = IconRegistry.fetch("bilimbi-impersonate")
    assert icon.view_box == "0 0 24 24"
    assert icon.fill == "none"
    assert length(icon.paths) == 4

    assert {:ok, hero_icon} = IconRegistry.fetch("hero-impersonate")
    assert hero_icon == icon
  end

  test "maps each familiar action meaning to one Heroicon" do
    assert IconRegistry.actions() == %{
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
             "bilimbi-plus" => "hero-plus",
             "bilimbi-pencil" => "hero-pencil",
             "bilimbi-link-slash" => "hero-link-slash",
             "bilimbi-x-mark" => "hero-x-mark"
           }
  end

  test "registers each literal bilimbi-* call site name to its matching Heroicon" do
    assert {:ok, "hero-plus"} = IconRegistry.action("bilimbi-plus")
    assert {:ok, "hero-pencil"} = IconRegistry.action("bilimbi-pencil")
    assert {:ok, "hero-link-slash"} = IconRegistry.action("bilimbi-link-slash")
    assert {:ok, "hero-x-mark"} = IconRegistry.action("bilimbi-x-mark")

    assert {:hero, "hero-plus"} = IconRegistry.lookup("bilimbi-plus")
    assert {:hero, "hero-pencil"} = IconRegistry.lookup("bilimbi-pencil")
    assert {:hero, "hero-link-slash"} = IconRegistry.lookup("bilimbi-link-slash")
    assert {:hero, "hero-x-mark"} = IconRegistry.lookup("bilimbi-x-mark")

    # Each of the four resolves to a genuinely different Heroicon, so the
    # "add", "edit", "unlink" and "remove" call sites that use them stop
    # rendering the same fallback glyph.
    resolved =
      for name <- ~w(bilimbi-plus bilimbi-pencil bilimbi-link-slash bilimbi-x-mark) do
        {:hero, hero_name} = IconRegistry.lookup(name)
        hero_name
      end

    assert Enum.uniq(resolved) == resolved
  end

  test "renders the previously-broken call site names as distinct, correct icons" do
    assigns = %{}

    plus_html =
      rendered_to_string(~H"""
      <.icon name="bilimbi-plus" class="size-3.5" />
      """)

    pencil_html =
      rendered_to_string(~H"""
      <.icon name="bilimbi-pencil" class="size-3.5" />
      """)

    link_slash_html =
      rendered_to_string(~H"""
      <.icon name="bilimbi-link-slash" class="size-3.5" />
      """)

    x_mark_html =
      rendered_to_string(~H"""
      <.icon name="bilimbi-x-mark" class="size-3.5" />
      """)

    assert plus_html =~ "hero-plus"
    assert pencil_html =~ "hero-pencil"
    assert link_slash_html =~ "hero-link-slash"
    assert x_mark_html =~ "hero-x-mark"

    # None of them fall back to the generic, meaningless glyph anymore.
    refute plus_html =~ "hero-square-3-stack-3d"
    refute pencil_html =~ "hero-square-3-stack-3d"
    refute link_slash_html =~ "hero-square-3-stack-3d"
    refute x_mark_html =~ "hero-square-3-stack-3d"

    # And the four rendered outputs are pairwise distinct.
    assert Enum.uniq([plus_html, pencil_html, link_slash_html, x_mark_html]) ==
             [plus_html, pencil_html, link_slash_html, x_mark_html]
  end

  test "does not register logout or an unknown hero- name" do
    assert :error = IconRegistry.fetch("unknown-icon")
    assert :error = IconRegistry.action("unknown-icon")
    assert :error = IconRegistry.action("hero-arrow-right-on-rectangle")
    assert :error = IconRegistry.lookup("hero-arrow-right-on-rectangle")
    assert :error = IconRegistry.fetch("create")
    assert :error = IconRegistry.lookup("hero-plus")
  end

  test "raises for an unregistered name that is not a hero- passthrough" do
    assert_raise ArgumentError, ~r/no icon named "unknown-icon"/, fn ->
      IconRegistry.lookup("unknown-icon")
    end
  end

  test "raises when the icon component itself is asked for an unregistered name" do
    assigns = %{}

    assert_raise ArgumentError, ~r/no icon named "totally-bogus-name"/, fn ->
      rendered_to_string(~H"""
      <.icon name="totally-bogus-name" class="size-4" />
      """)
    end
  end

  test "renders a named action as the chosen Heroicon class" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.icon name="create" class="size-4" />
      """)

    assert html =~ "hero-plus"
    assert html =~ "size-4"
  end

  test "still passes unknown hero- names through to generated Heroicons" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.icon name="hero-plus" class="size-4" />
      """)

    assert html =~ "hero-plus"
  end
end
