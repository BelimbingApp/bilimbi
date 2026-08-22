defmodule BilimbiWeb.AppShellJsTest do
  @moduledoc """
  LiveViewTest cannot drive the colocated hook. These pin the modal-drawer
  contract in the source so a later edit cannot drop inert/aria-modal
  without a failing test.
  """

  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/app_shell.js", __DIR__)

  setup do
    {:ok, source: File.read!(@hook)}
  end

  test "closed mobile drawer is inert", %{source: source} do
    assert source =~ ~S[this.sidebar.toggleAttribute("inert", hideDrawer)]
    assert source =~ ~S[this.sidebar.setAttribute("aria-hidden", hideDrawer ? "true" : "false")]
  end

  test "open mobile drawer is a modal dialog and inerts the rest of the shell", %{source: source} do
    assert source =~ ~S[this.sidebar.setAttribute("aria-modal", drawerOpen ? "true" : "false")]
    assert source =~ ~S[this.sidebar.setAttribute("role", drawerOpen ? "dialog" : "navigation")]
    assert source =~ "this.content, this.statusbar, this.topbarMain"
    assert source =~ ~S[region.toggleAttribute("inert", drawerOpen)]
  end

  test "desktop rail width can be dragged", %{source: source} do
    assert source =~ "startDrag"
    assert source =~ "sidebarWidth"
    assert source =~ ~S[this.drag = this.el.querySelector("#app-sidebar-drag")]
  end

  test "page-header pin controls use the same saved items as sidebar pins", %{source: source} do
    assert source =~ ~S[this.root?.addEventListener("click", this.onNav)]
    assert source =~ ~S[if (pin && this.root?.contains(pin))]
    assert source =~ ~S{this.root.querySelectorAll("[data-nav-pin]")}
  end

  test "record pins persist a safe label and URL alongside legacy navigation IDs", %{
    source: source
  } do
    assert source =~ "normalizePinnedItem"
    assert source =~ "normalizePinnedUrl"
    assert source =~ ~S[pin.dataset.navPinRecord === "true"]
    assert source =~ ~S[unpin.dataset.navUnpin = key]
    assert source =~ ~S[link.setAttribute("data-phx-link", "redirect")]
    assert source =~ "url:${item.url}"
  end

  test "Escape closes the drawer and the toggle stays outside the inert region", %{source: source} do
    assert source =~ ~S[if (event.key === "Escape")]
    assert source =~ "this.closeDrawer()"
    assert source =~ ~S[this.toggle = this.el.querySelector("#app-sidebar-toggle")]
    refute source =~ "this.topbar.toggleAttribute"
  end
end
