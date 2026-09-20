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
             "reveal" => "hero-eye",
             "conceal" => "hero-eye-slash",
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
             "manage" => "hero-cog-6-tooth",
             "theme-light" => "hero-sun",
             "theme-dark" => "hero-moon",
             "theme-system" => "hero-computer-desktop",
             "clock" => "hero-clock",
             "sidebar" => "hero-bars-3",
             "save" => "hero-check-circle",
             "confirm" => "hero-check",
             "back" => "hero-arrow-left",
             "history" => "hero-clock",
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
             "status" => "hero-signal"
           }
  end

  test "resolves each action the address and employee panels name to its own Heroicon" do
    assert {:hero, "hero-plus"} = IconRegistry.lookup("create")
    assert {:hero, "hero-pencil"} = IconRegistry.lookup("edit")
    assert {:hero, "hero-link-slash"} = IconRegistry.lookup("unlink")
    assert {:hero, "hero-x-mark"} = IconRegistry.lookup("close")
  end

  test "renders those four actions as distinct icons rather than one fallback glyph" do
    rendered =
      for name <- ~w(create edit unlink close) do
        assigns = %{name: name}

        rendered_to_string(~H"""
        <.icon name={@name} class="size-3.5" />
        """)
      end

    [create_html, edit_html, unlink_html, close_html] = rendered

    assert create_html =~ "hero-plus"
    assert edit_html =~ "hero-pencil"
    assert unlink_html =~ "hero-link-slash"
    assert close_html =~ "hero-x-mark"

    refute Enum.any?(rendered, &(&1 =~ "hero-square-3-stack-3d"))
    assert Enum.uniq(rendered) == rendered
  end

  test "refuses the bilimbi-* misspellings of those four actions" do
    for name <- ~w(bilimbi-plus bilimbi-pencil bilimbi-link-slash bilimbi-x-mark) do
      assert :error = IconRegistry.action(name)
      assert :error = IconRegistry.fetch(name)

      assert_raise ArgumentError, ~r/no icon named "#{name}"/, fn ->
        IconRegistry.lookup(name)
      end
    end
  end

  test "renderable?/1 answers exactly whether lookup/1 raises" do
    for name <- ~w(bilimbi-pin bilimbi-impersonate create edit unlink close hero-made-up) do
      assert IconRegistry.renderable?(name)
      refute lookup_raises?(name)
    end

    for name <- ~w(bilimbi-plus bilimbi-x-mark heroicon-o-bell unknown-icon) do
      refute IconRegistry.renderable?(name)
      assert lookup_raises?(name)
    end

    refute IconRegistry.renderable?(nil)
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

  defp lookup_raises?(name) do
    IconRegistry.lookup(name)
    false
  rescue
    ArgumentError -> true
  end
end
