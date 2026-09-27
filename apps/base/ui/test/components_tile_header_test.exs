defmodule Bilimbi.Base.UI.ComponentsTileHeaderTest do
  @moduledoc """
  Tests for `<.tile_header>`, the bar above a workspace tile, and
  `<.split_handle>`, the divider between two tiles.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  alias Phoenix.LiveView.JS

  defp tile_bar(assigns) do
    assigns = assign_new(assigns, :focused, fn -> false end)
    assigns = assign_new(assigns, :monocle, fn -> false end)
    assigns = assign_new(assigns, :following, fn -> false end)
    assigns = assign_new(assigns, :on_follow, fn -> nil end)

    ~H"""
    <.tile_header
      id="tile-t1-header"
      title="Companies"
      focused={@focused}
      monocle={@monocle}
      following={@following}
      on_follow={@on_follow}
      open_alone="/companies?page=2"
      on_focus={JS.push("focus-tile", value: %{id: "t1"})}
      on_close={JS.push("close-tile", value: %{id: "t1"})}
      on_monocle={JS.push("toggle-monocle", value: %{id: "t1"})}
      on_split={JS.push("toggle-split", value: %{id: "t1"})}
      on_swap={JS.push("swap-tile", value: %{id: "t1"})}
    />
    """
  end

  # The element with `id`, as the one tag that opens it; LazyHTML is the
  # host's dependency, not this package's.
  defp attribute(html, "#" <> id, name) do
    with [tag] <- Regex.run(~r/<[a-z]+[^>]*\bid="#{Regex.escape(id)}"[^>]*>/, html),
         [_, value] <- Regex.run(~r/\s#{Regex.escape(name)}="([^"]*)"/, tag) do
      value
    else
      _ -> nil
    end
  end

  test "the title focuses the tile and the menu carries every operation" do
    html = render_component(&tile_bar/1, %{})

    assert attribute(html, "#tile-t1-header", "phx-hook") == "DisclosureDismiss"
    assert attribute(html, "#tile-t1-header-title", "phx-click") =~ "focus-tile"
    assert attribute(html, "#tile-t1-header-menu", "aria-expanded") == "false"
    assert attribute(html, "#tile-t1-header-menu", "aria-controls") == "tile-t1-header-menu-items"
    assert attribute(html, "#tile-t1-header-menu", "aria-label") == "Tile menu: Companies"

    assert attribute(html, "#tile-t1-header-monocle", "phx-click") =~ "toggle-monocle"
    assert attribute(html, "#tile-t1-header-swap", "phx-click") =~ "swap-tile"
    assert attribute(html, "#tile-t1-header-split", "phx-click") =~ "toggle-split"
    assert attribute(html, "#tile-t1-header-close", "phx-click") =~ "close-tile"
    assert attribute(html, "#tile-t1-header-open-alone", "href") == "/companies?page=2"
    assert attribute(html, "#tile-t1-header-open-alone", "data-phx-link") == "redirect"

    # Each entry closes the menu in the same click.
    assert attribute(html, "#tile-t1-header-close", "phx-click") =~
             ~s([&quot;aria-expanded&quot;,&quot;false&quot;])

    assert html =~ "Monocle: fill the workspace"
  end

  test "focus and monocle change the words and the accent, never the controls" do
    plain = render_component(&tile_bar/1, %{})
    focused = render_component(&tile_bar/1, %{focused: true, monocle: true})

    refute attribute(plain, "#tile-t1-header", "class") =~ "text-brand-strong"
    assert attribute(focused, "#tile-t1-header", "class") =~ "text-brand-strong"
    assert focused =~ "Show every tile"
    refute focused =~ "Monocle: fill the workspace"
    assert attribute(focused, "#tile-t1-header-close", "phx-click") =~ "close-tile"
  end

  test "following is offered only for a page with a record, and shown when on" do
    plain = render_component(&tile_bar/1, %{})
    refute plain =~ "tile-t1-header-follow"
    refute plain =~ "tile-t1-header-following"

    offered =
      render_component(&tile_bar/1, %{on_follow: JS.push("follow-tile", value: %{id: "t1"})})

    assert attribute(offered, "#tile-t1-header-follow", "phx-click") =~ "follow-tile"
    assert offered =~ "Follow selections"
    refute offered =~ "tile-t1-header-following"

    following =
      render_component(&tile_bar/1, %{
        following: true,
        on_follow: JS.push("unfollow-tile", value: %{id: "t1"})
      })

    assert attribute(following, "#tile-t1-header-follow", "phx-click") =~ "unfollow-tile"
    assert following =~ "Stop following"
    assert attribute(following, "#tile-t1-header-following", "title") == "Follows selections"
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
            style="left: 50%; top: 0%; height: 100%"
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
    assert attribute(html, "#split-s3", "style") == "left: 50%; top: 0%; height: 100%"
    assert attribute(html, "#split-s3", "class") =~ "cursor-col-resize"

    assert attribute(html, "#split-s4", "aria-orientation") == "horizontal"
    assert attribute(html, "#split-s4", "class") =~ "cursor-row-resize"
    assert attribute(html, "#split-s4", "style") in [nil, ""]
  end
end
