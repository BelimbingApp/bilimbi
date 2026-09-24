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

  # A minimal DOM and a durable pin API. The hook runs against it in node,
  # so the tests below observe the requests it sends and the shell it renders.
  @pin_harness ~S"""
  class El {
    constructor(tag = "div", props = {}) {
      Object.assign(this, {tagName: tag, dataset: {}, style: {}, children: [], parentElement: null, className: ""}, props)
      this.attrs = new Map()
    }
    append(...nodes) { for (const node of nodes) { node.parentElement = this; this.children.push(node) } }
    replaceChildren() { this.children = [] }
    setAttribute(name, value) { this.attrs.set(name, String(value)) }
    getAttribute(name) { return this.attrs.get(name) ?? null }
    hasAttribute(name) { return this.attrs.has(name) }
    toggleAttribute(name, on) { on ? this.attrs.set(name, "") : this.attrs.delete(name) }
    focus() { document.activeElement = this }
    matches(selector) {
      if (selector.startsWith(".")) return this.className.split(" ").includes(selector.slice(1))
      const data = selector.match(/^\[data-([a-z-]+)\]$/)
      if (!data) return false
      const key = data[1].replace(/-([a-z])/g, (_m, c) => c.toUpperCase())
      return this.dataset[key] !== undefined
    }
    descendants() { return this.children.flatMap((child) => [child, ...child.descendants()]) }
    querySelectorAll(selector) { return this.descendants().filter((node) => node.matches(selector)) }
    querySelector(selector) { return this.querySelectorAll(selector)[0] ?? null }
    closest(selector) {
      for (let node = this; node; node = node.parentElement) if (node.matches(selector)) return node
      return null
    }
    contains(node) { return !!node && (node === this || this.descendants().includes(node)) }
  }

  const storage = new Map()
  globalThis.window = {
    location: {origin: "https://bilimbi.test"},
    localStorage: {
      getItem: (key) => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: (key) => storage.delete(key),
    },
  }

  const navItem = new El("a", {id: "nav-companies", href: "https://bilimbi.test/companies"})
  navItem.dataset.navLabel = "Companies"
  const navPin = new El("button")
  navPin.dataset.navPin = "nav-companies"
  navPin.setAttribute("aria-label", "Pin Companies")
  const sidebar = new El("nav")
  sidebar.append(navItem, navPin)
  const pinnedItems = new El()
  const announcement = new El("p")
  const root = new El()
  root.append(sidebar, pinnedItems, announcement)

  globalThis.document = {
    activeElement: null,
    createElement: (tag) => new El(tag),
    getElementById: (id) => root.descendants().find((node) => node.id === id) ?? null,
    querySelector: () => null,
  }

  let serverPins = []
  let nextId = 1
  let failReorder = null
  const requests = []
  const reply = (body, status = 200) => ({ok: status < 400, status, json: async () => body})
  globalThis.fetch = async (path, options = {}) => {
    const body = options.body ? JSON.parse(options.body) : null
    requests.push({path, method: options.method || "GET", body})
    if (path === "/api/pins") return reply({pins: serverPins})
    if (path === "/api/pins/toggle") {
      const found = serverPins.find((pin) => pin.url === body.url)
      serverPins = found
        ? serverPins.filter((pin) => pin !== found)
        : [...serverPins, {id: nextId++, label: body.label, url: body.url, icon: body.icon}]
      return reply({pins: serverPins})
    }
    if (path === "/api/pins/reorder") {
      if (failReorder) return failReorder
      serverPins = body.pins.map(({id}) => serverPins.find((pin) => String(pin.id) === String(id)))
      return reply({pins: serverPins})
    }
    return reply({}, 404)
  }

  const flush = async () => { for (let i = 0; i < 20; i++) await new Promise((resolve) => setImmediate(resolve)) }

  const hook = Object.create(AppShell)
  Object.assign(hook, {
    root, sidebar, pinnedItems, pinned: {hidden: true}, pinnedAnnouncement: announcement,
    rail: false, impersonating: false, pinnedEntries: [],
    servedRoutes: ["/companies", "/companies/:id", "/users"],
  })

  const rows = () => pinnedItems.children.map((row) => ({
    key: row.dataset.pinnedItem,
    label: row.querySelector(".app-nav-label").textContent,
    href: row.querySelector(".app-pinned-link").href,
  }))
  const move = (key, direction) =>
    pinnedItems.querySelectorAll("[data-nav-move]").find((node) =>
      node.dataset.pinnedItem === key && node.dataset.navMove === direction
    )
  """

  defp run_pin_hook(body) do
    controls = File.read!(Path.join(Path.dirname(@hook), "shell_controls.js")) |> Base.encode64()

    source =
      File.read!(@hook)
      |> String.replace("\"./shell_controls\"", "\"data:text/javascript;base64,#{controls}\"")
      |> Base.encode64()

    script = """
    const {default: AppShell} = await import("data:text/javascript;base64,#{source}")
    #{@pin_harness}
    #{body}
    """

    assert {output, 0} = System.cmd("node", ["--input-type=module", "--eval", script])
    JSON.decode!(String.trim(output))
  end

  test "pins hydrate from the API and legacy browser pins migrate in their saved order" do
    result =
      run_pin_hook(~S"""
      serverPins = [{id: nextId++, label: "Users", url: "/users", icon: null}]
      storage.set("sidebarPinnedItems", JSON.stringify([
        {id: "nav-companies"},
        {label: "Company 1", url: "/companies/1/?b=2&a=1#top"},
        {label: "Users again", url: "/users"},
      ]))

      await hook.loadPinnedItems()

      console.log(JSON.stringify({
        requests: requests.map(({path, method, body}) => ({path, method, body})),
        rows: rows(),
        legacy: storage.has("sidebarPinnedItems"),
        pressed: navPin.getAttribute("aria-pressed"),
        title: navPin.title,
      }))
      """)

    assert [
             %{"path" => "/api/pins", "method" => "GET"},
             %{
               "path" => "/api/pins/toggle",
               "body" => %{"label" => "Companies", "url" => "/companies"}
             },
             %{"path" => "/api/pins/toggle", "body" => %{"url" => "/companies/1?a=1&b=2"}},
             %{
               "path" => "/api/pins/reorder",
               "body" => %{"pins" => [%{"id" => "2"}, %{"id" => "3"}, %{"id" => "1"}]}
             }
           ] = result["requests"]

    assert Enum.map(result["rows"], & &1["label"]) == ["Companies", "Company 1", "Users"]
    assert result["legacy"] == false
    assert result["pressed"] == "true"
    assert result["title"] == "Unpin Companies"
  end

  test "a keyboard move button reorders durably, announces the move, and keeps focus" do
    result =
      run_pin_hook(~S"""
      serverPins = [
        {id: nextId++, label: "Company 1", url: "/companies/1"},
        {id: nextId++, label: "Users", url: "/users"},
      ]
      await hook.loadPinnedItems()

      const moveDown = move("pin:1", "down")
      const first = {down: moveDown.dataset.navMove, disabledUp: move("pin:1", "up").disabled}
      hook.onSidebarClick({target: moveDown, preventDefault: () => {}})
      await flush()

      const focusedRow = document.activeElement?.parentElement?.dataset.pinnedItem
      console.log(JSON.stringify({
        first,
        reorder: requests.filter(({path}) => path === "/api/pins/reorder").map(({body}) => body),
        rows: rows().map(({key}) => key),
        announcement: announcement.textContent,
        focusedRow,
      }))
      """)

    assert result["first"] == %{"down" => "down", "disabledUp" => true}
    assert result["reorder"] == [%{"pins" => [%{"id" => "2"}, %{"id" => "1"}]}]
    assert result["rows"] == ["pin:2", "pin:1"]
    assert result["announcement"] == "Moved Company 1 down."
    assert result["focusedRow"] == "pin:1"
  end

  test "a dragged pin moves at once and returns to its slot when the server refuses" do
    result =
      run_pin_hook(~S"""
      serverPins = [
        {id: nextId++, label: "Company 1", url: "/companies/1"},
        {id: nextId++, label: "Users", url: "/users"},
      ]
      await hook.loadPinnedItems()

      let refuse
      failReorder = new Promise((resolve) => { refuse = () => resolve(reply({error: "x"}, 500)) })
      hook.draggedPinnedKey = "pin:2"
      hook.dropPinnedDrag({target: pinnedItems.children[0], preventDefault: () => {}})
      const optimistic = rows().map(({key}) => key)

      refuse()
      await flush()

      console.log(JSON.stringify({
        optimistic,
        recovered: rows().map(({key}) => key),
        announcement: announcement.textContent,
      }))
      """)

    assert result["optimistic"] == ["pin:2", "pin:1"]
    assert result["recovered"] == ["pin:1", "pin:2"]
    assert result["announcement"] == "Unable to reorder pinned pages."
  end

  test "an impersonated shell shows the user's pins read-only and leaves browser pins alone" do
    result =
      run_pin_hook(~S"""
      hook.impersonating = true
      serverPins = [{id: nextId++, label: "Users", url: "/users"}, {id: nextId++, label: "Gone", url: "/removed"}]
      storage.set("sidebarPinnedItems", JSON.stringify([{id: "nav-companies"}]))

      await hook.loadPinnedItems()
      hook.onSidebarClick({target: navPin, preventDefault: () => {}})
      await flush()

      const controls = pinnedItems.querySelectorAll("[data-nav-move]").concat(pinnedItems.querySelectorAll("[data-nav-unpin]"))
      console.log(JSON.stringify({
        requests: requests.map(({path, method}) => `${method} ${path}`),
        rows: rows().map(({label}) => label),
        legacy: storage.has("sidebarPinnedItems"),
        controlsDisabled: controls.length > 0 && controls.every((node) => node.disabled),
        draggable: pinnedItems.children.map((row) => row.draggable),
        navPinDisabled: navPin.disabled,
      }))
      """)

    assert result["requests"] == ["GET /api/pins"]
    assert result["rows"] == ["Users"]
    assert result["legacy"] == true
    assert result["controlsDisabled"] == true
    assert result["draggable"] == [false]
    assert result["navPinDisabled"] == true
  end

  test "a saved object-form navigation pin survives reload and renders" do
    controls = File.read!(Path.join(Path.dirname(@hook), "shell_controls.js")) |> Base.encode64()

    source =
      File.read!(@hook)
      |> String.replace("\"./shell_controls\"", "\"data:text/javascript;base64,#{controls}\"")

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
    hook.servedRoutes = ["/companies"]
    hook.pinnedEntries = hook.readLegacyPinnedItems()
    hook.renderPinnedItems()

    console.log(JSON.stringify({entries: hook.pinnedEntries, rows: rows.length}))
    """

    assert {"{\"entries\":[{\"navId\":\"nav-companies\"}],\"rows\":1}\n", 0} =
             System.cmd("node", ["--input-type=module", "--eval", script])
  end

  test "updated() restores a server-reset aria-pressed through apply() alone (#685)" do
    # A LiveView patch re-renders a pinned page's title pin with the server
    # default aria-pressed="false". The hook's single sync path —
    # updated() -> apply() -> renderPinnedItems() — must restore the stored
    # pressed state without any second render call.
    controls = File.read!(Path.join(Path.dirname(@hook), "shell_controls.js")) |> Base.encode64()

    source =
      File.read!(@hook)
      |> String.replace("\"./shell_controls\"", "\"data:text/javascript;base64,#{controls}\"")

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
    hook.servedRoutes = ["/companies/:id"]
    hook.pinnedEntries = hook.readLegacyPinnedItems()

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
