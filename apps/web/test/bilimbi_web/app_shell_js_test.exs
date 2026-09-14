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

  test "a saved object-form navigation pin survives reload and renders" do
    source = File.read!(@hook)
    encoded_source = Base.encode64(source)

    script = """
    const {default: AppShell} = await import("data:text/javascript;base64,#{encoded_source}")
    const storage = new Map([["sidebarPinnedItems", JSON.stringify([{id: "nav-companies"}])]])

    globalThis.window = {
      location: {origin: "https://bilimbi.test"},
      localStorage: {
        getItem: (key) => storage.get(key) ?? null,
        setItem: (key, value) => storage.set(key, value),
      },
    }

    const element = () => ({
      dataset: {},
      append: () => {},
      setAttribute: () => {},
      hasAttribute: () => false,
      getAttribute: () => null,
      querySelector: () => null,
    })

    const navItem = {
      ...element(),
      dataset: {navLabel: "Companies"},
      href: "/companies",
    }

    const rows = []
    globalThis.document = {
      getElementById: (id) => (id === "nav-companies" ? navItem : null),
      createElement: element,
    }

    const hook = Object.create(AppShell)
    hook.sidebar = {contains: (item) => item === navItem}
    hook.root = {querySelectorAll: () => []}
    hook.pinned = {hidden: true}
    hook.pinnedItems = {
      replaceChildren: () => rows.splice(0),
      append: (row) => rows.push(row),
    }
    hook.rail = false
    hook.pinnedEntries = hook.readPinnedItems()
    hook.renderPinnedItems()

    console.log(JSON.stringify({entries: hook.pinnedEntries, rows: rows.length}))
    """

    assert {"{\"entries\":[{\"id\":\"nav-companies\"}],\"rows\":1}\n", 0} =
             System.cmd("node", ["--input-type=module", "--eval", script])
  end

  test "updated() restores a server-reset aria-pressed through apply() alone (#685)" do
    # A LiveView patch re-renders a pinned page's title pin with the server
    # default aria-pressed="false". The hook's single sync path —
    # updated() -> apply() -> renderPinnedItems() — must restore the stored
    # pressed state without any second render call.
    source = File.read!(@hook)
    encoded_source = Base.encode64(source)

    script = """
    const {default: AppShell} = await import("data:text/javascript;base64,#{encoded_source}")

    const stored = [{label: "Administration / Companies / Bilimbi Development", url: "/companies/1"}]
    const storage = new Map([["sidebarPinnedItems", JSON.stringify(stored)]])

    globalThis.window = {
      location: {origin: "https://bilimbi.test"},
      localStorage: {
        getItem: (key) => storage.get(key) ?? null,
        setItem: (key, value) => storage.set(key, value),
      },
    }

    const element = () => ({
      dataset: {},
      style: {},
      append: () => {},
      setAttribute: () => {},
      toggleAttribute: () => {},
      hasAttribute: () => false,
      getAttribute: () => null,
      querySelector: () => null,
      querySelectorAll: () => [],
    })

    globalThis.document = {getElementById: () => null, createElement: element}

    // The title pin as the server just re-rendered it: pressed state lost.
    const attrs = new Map([
      ["aria-pressed", "false"],
      ["aria-label", "Pin this company to sidebar"],
    ])
    const titlePin = {
      dataset: {
        navPin: "record",
        navPinRecord: "true",
        navPinLabel: "Administration / Companies / Bilimbi Development",
        navPinUrl: "/companies/1",
      },
      title: "Pin this company to sidebar",
      getAttribute: (name) => attrs.get(name) ?? null,
      setAttribute: (name, value) => attrs.set(name, value),
    }

    let renders = 0
    const hook = Object.create(AppShell)
    hook.root = {
      dataset: {},
      querySelectorAll: (sel) => (sel === "[data-nav-pin]" ? [titlePin] : []),
    }
    hook.sidebar = element()
    hook.toggle = element()
    hook.content = element()
    hook.statusbar = element()
    hook.topbarMain = element()
    hook.backdrop = element()
    hook.mq = {matches: true}
    hook.rail = false
    hook.drawerOpen = false
    hook.width = 240
    hook.expandedBranches = {}
    hook.pinned = {hidden: true}
    hook.pinnedItems = {replaceChildren: () => {}, append: () => renders++}
    hook.pinnedEntries = hook.readPinnedItems()

    hook.updated()

    console.log(
      JSON.stringify({
        pressed: attrs.get("aria-pressed"),
        datasetPinned: titlePin.dataset.pinned,
        title: titlePin.title,
        rows: renders,
      })
    )
    """

    assert {output, 0} = System.cmd("node", ["--input-type=module", "--eval", script])

    assert %{
             "pressed" => "true",
             "datasetPinned" => "true",
             "title" => "Unpin this company to sidebar",
             "rows" => 1
           } = JSON.decode!(String.trim(output))
  end

  test "Escape closes the drawer and the toggle stays outside the inert region", %{source: source} do
    assert source =~ ~S[if (event.key === "Escape")]
    assert source =~ "this.closeDrawer()"
    assert source =~ ~S[this.toggle = this.el.querySelector("#app-sidebar-toggle")]
    refute source =~ "this.topbar.toggleAttribute"
  end
end
