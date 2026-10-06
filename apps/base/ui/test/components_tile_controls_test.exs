defmodule Bilimbi.Base.UI.ComponentsTileControlsTest do
  @moduledoc """
  Tests for `<.tile_controls>`, the grip and menu floating over a workspace
  tile, and `<.split_handle>`, the divider between two tiles.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  use Bilimbi.Base.UI.Components

  alias Phoenix.LiveView.JS

  defp controls(assigns) do
    assigns = assign_new(assigns, :focused, fn -> false end)
    assigns = assign_new(assigns, :following, fn -> false end)
    assigns = assign_new(assigns, :master_layout, fn -> false end)
    assigns = assign_new(assigns, :master_tile, fn -> false end)

    ~H"""
    <.tile_controls
      id="tile-t1-controls"
      title="Companies"
      focused={@focused}
      following={@following}
      master_layout={@master_layout}
      master_tile={@master_tile}
      on_split={JS.push("toggle-split", value: %{id: "t1"})}
      on_close={JS.push("close-tile", value: %{id: "t1"})}
    />
    """
  end

  defp attribute(html, selector, name) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute(name)
    |> List.first()
  end

  defp entry_ids(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#tile-t1-controls button")
    |> LazyHTML.attribute("id")
  end

  test "the menu is a named disclosure offering only the split flip and close" do
    html = render_component(&controls/1, %{})

    assert attribute(html, "#tile-t1-controls", "phx-hook") == "DisclosureDismiss"
    assert attribute(html, "#tile-t1-controls-menu", "aria-expanded") == "false"

    assert attribute(html, "#tile-t1-controls-menu", "aria-controls") ==
             "tile-t1-controls-menu-items"

    assert attribute(html, "#tile-t1-controls-menu", "aria-label") == "Tile menu: Companies"

    assert entry_ids(html) == [
             "tile-t1-controls-menu",
             "tile-t1-controls-split",
             "tile-t1-controls-close"
           ]

    assert attribute(html, "#tile-t1-controls-split", "phx-click") =~ "toggle-split"
    assert attribute(html, "#tile-t1-controls-close", "phx-click") =~ "close-tile"
    assert html =~ "Flip split direction"

    # Each entry closes the menu in the same click, and the flip, which
    # leaves the tile in place, hands focus back to the trigger.
    closed = ~s("attr":["aria-expanded","false"])
    assert attribute(html, "#tile-t1-controls-close", "phx-click") =~ closed
    assert attribute(html, "#tile-t1-controls-split", "phx-click") =~ closed
    assert attribute(html, "#tile-t1-controls-split", "phx-click") =~ ~s(["focus",)
    refute attribute(html, "#tile-t1-controls-close", "phx-click") =~ ~s(["focus",)
  end

  test "the grip is a pointer handle that takes no focus" do
    html = render_component(&controls/1, %{})

    assert attribute(html, "span#tile-t1-controls-grip[data-tile-grip]", "title") ==
             "Drag onto another tile to swap"

    assert attribute(html, "#tile-t1-controls-grip", "tabindex") == nil
  end

  test "master and following are marked, and master mode renames the split entry" do
    plain = render_component(&controls/1, %{})
    refute plain =~ "tile-t1-controls-master"
    refute plain =~ "tile-t1-controls-following"

    master = render_component(&controls/1, %{master_layout: true, master_tile: true})
    assert master =~ ~s(id="tile-t1-controls-master")
    assert master =~ "Flip master direction"
    refute master =~ "Flip split direction"

    following = render_component(&controls/1, %{following: true})
    assert attribute(following, "#tile-t1-controls-following", "title") == "Follows selections"
  end

  test "a split handle is a focusable separator oriented like the line it draws" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <.split_handle
            id="split-s3"
            direction={:h}
            label="Resize Companies and Users"
            data-place="left: 50%; top: 0%; height: 100%"
            data-split="s3"
            data-rect="0 0 1 1"
          />
          <.split_handle id="split-s4" direction={:v} label="Resize Users and Employees" />
          """
        end,
        %{}
      )

    assert attribute(html, "#split-s3", "role") == "separator"
    assert attribute(html, "#split-s3", "tabindex") == "0"
    assert attribute(html, "#split-s3", "aria-orientation") == "vertical"
    assert attribute(html, "#split-s3", "aria-label") == "Resize Companies and Users"
    assert attribute(html, "#split-s3", "data-split") == "s3"
    assert attribute(html, "#split-s3", "data-direction") == "h"
    assert attribute(html, "#split-s3", "data-place") == "left: 50%; top: 0%; height: 100%"
    # The policy forbids inline style, so the handle never renders one.
    assert attribute(html, "#split-s3", "style") == nil
    assert attribute(html, "#split-s3", "class") =~ "cursor-col-resize"

    assert attribute(html, "#split-s4", "aria-orientation") == "horizontal"
    assert attribute(html, "#split-s4", "class") =~ "cursor-row-resize"
    assert attribute(html, "#split-s4", "style") == nil
  end
end
