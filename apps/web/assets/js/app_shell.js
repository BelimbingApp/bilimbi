import ShellControls from "./shell_controls.js"

// Authenticated shell chrome. Owns only what the server cannot: the desktop
// rail choice (localStorage), pin hydration from `data-pins` (and migration), the mobile
// drawer, Escape/backdrop close, returning focus to the toggle, and pointing
// each row's "Open in a tile" link at the workspace from wherever the
// browser is. The top-bar display controls and account disclosure belong to
// ShellControls, which this hook drives through the same lifecycle.
// Navigation, capabilities, and status values stay server-rendered.
const DESKTOP = "(min-width: 1024px)"
const WORKSPACE = "/workspace"
const RAIL_WIDTH = 56
const MIN_WIDTH = 180
const MAX_WIDTH = 360
const DEFAULT_WIDTH = 240
const NAV_EXPANSION_STORAGE = "sidebarExpandedBranches"
const PINNED_STORAGE = "sidebarPinnedItems"
const FOCUSABLE =
  'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'

// One page as a workspace tree: a leaf escapes what the tree grammar reads
// (`%`, `(`, `)`, `,`), as `Bilimbi.Base.Tiling.Layout.encode/1` does.
const leaf = (page) =>
  page.replace(/[%(),]/g, (char) => `%${char.charCodeAt(0).toString(16).toUpperCase()}`)

const AppShell = {
  mounted() {
    this.root = this.el
    this.toggle = this.el.querySelector("#app-sidebar-toggle")
    this.sidebar = this.el.querySelector("#app-sidebar")
    this.backdrop = this.el.querySelector("#app-sidebar-backdrop")
    this.content = this.el.querySelector("#app-content")
    this.topbarMain = this.el.querySelector("#app-topbar-main")
    this.statusbar = this.el.querySelector("#app-statusbar")
    this.drag = this.el.querySelector("#app-sidebar-drag")
    this.pinned = this.el.querySelector("#app-pinned")
    this.pinnedItems = this.el.querySelector("#app-pinned-items")
    this.pinnedAnnouncement = this.el.querySelector("#app-pinned-announcement")
    this.impersonating = this.el.dataset.impersonating === "true"
    this.servedRoutes = this.readServedRoutes()
    this.mq = window.matchMedia(DESKTOP)
    this.rail = window.localStorage.getItem("sidebarRail") === "1"
    this.width = this.readWidth()
    this.expandedBranches = this.readExpandedBranches()
    this.pinnedEntries = []
    this.drawerOpen = false
    this.lastFocus = null
    this.dragging = false
    this.draggedPinnedKey = null
    this.dropPinnedKey = null

    this.onToggle = () => this.toggleSidebar()
    this.onBackdrop = () => this.closeDrawer()
    this.onKey = (event) => this.onGlobalKey(event)
    this.onMq = () => this.onViewportChange()
    this.onNav = (event) => this.onSidebarClick(event)
    this.onDragStart = (event) => this.startDrag(event)
    this.onDragMove = (event) => this.moveDrag(event)
    this.onDragEnd = () => this.endDrag()
    this.onPinnedDragStart = (event) => this.startPinnedDrag(event)
    this.onPinnedDragOver = (event) => this.overPinnedDrag(event)
    this.onPinnedDrop = (event) => this.dropPinnedDrag(event)
    this.onPinnedDragEnd = () => this.endPinnedDrag()

    this.toggle?.addEventListener("click", this.onToggle)
    this.backdrop?.addEventListener("click", this.onBackdrop)
    this.root?.addEventListener("click", this.onNav)
    this.drag?.addEventListener("mousedown", this.onDragStart)
    this.pinnedItems?.addEventListener("dragstart", this.onPinnedDragStart)
    this.pinnedItems?.addEventListener("dragover", this.onPinnedDragOver)
    this.pinnedItems?.addEventListener("drop", this.onPinnedDrop)
    this.pinnedItems?.addEventListener("dragend", this.onPinnedDragEnd)
    window.addEventListener("keydown", this.onKey)
    this.mq.addEventListener("change", this.onMq)
    this.controls = new ShellControls(this)
    this.apply()
    this.loadPinnedItems()
  },

  disconnected() { this.controls?.connection(false) },
  reconnected() { this.controls?.connection(true) },

  updated() {
    this.controls?.apply()
    this.apply()
  },

  destroyed() {
    this.controls?.destroy()
    this.toggle?.removeEventListener("click", this.onToggle)
    this.backdrop?.removeEventListener("click", this.onBackdrop)
    this.root?.removeEventListener("click", this.onNav)
    this.drag?.removeEventListener("mousedown", this.onDragStart)
    this.pinnedItems?.removeEventListener("dragstart", this.onPinnedDragStart)
    this.pinnedItems?.removeEventListener("dragover", this.onPinnedDragOver)
    this.pinnedItems?.removeEventListener("drop", this.onPinnedDrop)
    this.pinnedItems?.removeEventListener("dragend", this.onPinnedDragEnd)
    window.removeEventListener("mousemove", this.onDragMove)
    window.removeEventListener("mouseup", this.onDragEnd)
    window.removeEventListener("keydown", this.onKey)
    this.mq?.removeEventListener("change", this.onMq)
  },

  desktop() {
    return this.mq.matches
  },

  readWidth() {
    const stored = Number.parseInt(window.localStorage.getItem("sidebarWidth"), 10)
    if (Number.isFinite(stored) && stored >= MIN_WIDTH && stored <= MAX_WIDTH) return stored
    return DEFAULT_WIDTH
  },

  readExpandedBranches() {
    try {
      const stored = JSON.parse(window.localStorage.getItem(NAV_EXPANSION_STORAGE) ?? "{}")
      return stored && typeof stored === "object" && !Array.isArray(stored) ? stored : {}
    } catch {
      return {}
    }
  },

  saveExpandedBranches() {
    window.localStorage.setItem(NAV_EXPANSION_STORAGE, JSON.stringify(this.expandedBranches))
  },

  readLegacyPinnedItems() {
    try {
      const stored = JSON.parse(window.localStorage.getItem(PINNED_STORAGE) ?? "[]")

      if (!Array.isArray(stored)) return []

      const items = stored
        .map((item) => this.normalizePinnedItem(item))
        .filter((item) => item)

      return items.filter(
        (item, index) =>
          items.findIndex((candidate) => this.pinnedItemKey(candidate) === this.pinnedItemKey(item)) ===
            index
      )
    } catch {
      return []
    }
  },

  readServedRoutes() {
    try {
      const routes = JSON.parse(this.root?.dataset.servedRoutes ?? "[]")
      return Array.isArray(routes) ? routes.filter((route) => typeof route === "string") : []
    } catch {
      return []
    }
  },

  normalizePinnedItem(item) {
    if (typeof item === "string") {
      const id = item.trim()
      return id ? {navId: id} : null
    }

    if (!item || typeof item !== "object" || Array.isArray(item)) return null

    const pinId = Number.isInteger(item.id) || (typeof item.id === "string" && /^\d+$/.test(item.id))
    if (pinId && typeof item.url === "string") {
      const url = this.normalizePinnedUrl(item.url)
      const label = typeof item.label === "string" ? item.label.trim() : ""
      return label && url
        ? {pinId: String(item.id), label, url, icon: item.icon || null}
        : null
    }

    const id = typeof item.id === "string" ? item.id.trim() : ""
    if (id) return {navId: id}

    const label = typeof item.label === "string" ? item.label.trim() : ""
    const url = this.normalizePinnedUrl(item.url)

    return label && url ? {label, url} : null
  },

  normalizePinnedUrl(url) {
    if (typeof url !== "string") return null

    try {
      const parsed = new URL(url, window.location.origin)
      if (parsed.origin !== window.location.origin) return null

      const path = parsed.pathname.replace(/\/+$/, "") || "/"
      const query = new URLSearchParams(parsed.search)
      query.sort()
      const search = query.toString()

      return search ? `${path}?${search}` : path
    } catch {
      return null
    }
  },

  pinnedItemKey(item) {
    if (item?.pinId) return `pin:${item.pinId}`
    if (item?.navId) return `nav:${item.navId}`
    if (item?.url) return `url:${item.url}`
    return null
  },

  pinnedUrl(item) {
    if (item?.url) return this.normalizePinnedUrl(item.url)
    if (item?.navId) return this.normalizePinnedUrl(this.navItem(item.navId)?.href)
    return null
  },

  isServedUrl(url) {
    const normalized = this.normalizePinnedUrl(url)
    if (!normalized) return false

    const path = normalized.split("?", 1)[0].split("#", 1)[0]
    const actual = path.split("/").filter(Boolean)

    return this.servedRoutes.some((route) => {
      const pattern = route.split("/", -1).filter(Boolean)
      return pattern.length === actual.length && pattern.every((segment, index) =>
        segment.startsWith(":") || segment === actual[index]
      )
    })
  },

  pinRequest(path, options = {}) {
    const headers = {...(options.headers || {}), Accept: "application/json"}
    if (options.method && options.method !== "GET") {
      headers["Content-Type"] = "application/json"
      headers["X-CSRF-Token"] = document.querySelector("meta[name='csrf-token']")?.content || ""
    }

    return fetch(path, {...options, headers, credentials: "same-origin"})
  },

  async loadPinnedItems() {
    const rendered = this.readRenderedPins()
    let pins = rendered

    if (!this.impersonating) {
      try {
        pins = await this.migrateLegacyPins(rendered)
      } catch (_error) {
        pins = rendered
      }
    }

    this.pinnedEntries = pins
    this.renderPinnedItems()
  },

  readRenderedPins() {
    try {
      const parsed = JSON.parse(this.el.dataset.pins || "[]")
      return this.acceptServerPins(Array.isArray(parsed) ? parsed : [])
    } catch {
      return []
    }
  },

  async fetchServerPins() {
    try {
      const response = await this.pinRequest("/api/pins")
      if (!response.ok) return null
      return this.acceptServerPins((await response.json()).pins)
    } catch (_error) {
      return null
    }
  },

  async migrateLegacyPins(pins) {
    const legacy = this.readLegacyPinnedItems()

    const legacyUrls = legacy
      .filter((item) => item.navId)
      .map((item) => ({item: this.migratablePinnedItem(item), url: this.pinnedUrl(item)}))
      .filter(({item, url}) => item && url && this.isServedUrl(url))

    for (const {item, url} of legacyUrls) {
      if (pins.some((pin) => this.pinnedUrl(pin) === url)) continue

      const imported = await this.pinRequest("/api/pins/toggle", {
        method: "POST",
        body: JSON.stringify({label: item.label, url, icon: null}),
      })
      if (!imported.ok) return pins
      pins = this.acceptServerPins((await imported.json()).pins)
    }

    // Remove the legacy key only after every import has succeeded. A rejected
    // toggle, a non-OK status, or a body that is not JSON leaves the key so
    // the next mount can retry. Pins already drawn from data-pins stay.
    window.localStorage.removeItem?.(PINNED_STORAGE)

    const urls = legacyUrls.map(({url}) => url)
    const ordered = [
      ...urls.map((url) => pins.find((pin) => this.pinnedUrl(pin) === url)).filter(Boolean),
      ...pins.filter((pin) => !urls.includes(this.pinnedUrl(pin))),
    ]

    if (ordered.some((pin, index) => pin.pinId !== pins[index]?.pinId)) {
      pins = (await this.reorderServerPins(ordered, false).catch(() => null)) || pins
    }

    return pins
  },

  migratablePinnedItem(item) {
    if (!item) return null
    if (item.navId) {
      const nav = this.navItem(item.navId)
      return nav ? {label: nav.dataset.navLabel, url: this.pinnedUrl(item)} : null
    }
    return item
  },

  acceptServerPins(pins) {
    if (!Array.isArray(pins)) return []
    return pins.map((pin) => this.normalizePinnedItem(pin)).filter((pin) =>
      pin && this.isServedUrl(pin.url)
    )
  },

  async reorderServerPins(pins, focus = true) {
    if (this.impersonating || !pins.length) return null
    const focusedKey = focus ? this.pinnedRow(document.activeElement)?.dataset.pinnedItem : null
    const response = await this.pinRequest("/api/pins/reorder", {
      method: "POST",
      body: JSON.stringify({pins: pins.map((pin) => ({id: pin.pinId}))}),
    })
    if (!response.ok) throw new Error(`Pin reorder failed with status ${response.status}`)
    const updated = this.acceptServerPins((await response.json()).pins)
    this.pinnedEntries = updated
    this.renderPinnedItems()
    if (focusedKey) this.focusPinnedKey(focusedKey)
    return updated
  },

  startDrag(event) {
    if (!this.desktop() || event.button !== 0) return
    event.preventDefault()
    this.dragging = true
    this.dragStartX = event.clientX
    this.dragStartWidth = this.rail ? RAIL_WIDTH : this.width
    document.documentElement.style.cursor = "col-resize"
    document.documentElement.style.userSelect = "none"
    window.addEventListener("mousemove", this.onDragMove)
    window.addEventListener("mouseup", this.onDragEnd)
  },

  moveDrag(event) {
    if (!this.dragging) return
    const next = this.dragStartWidth + (event.clientX - this.dragStartX)
    if (next < 80) {
      this.rail = true
    } else {
      this.rail = false
      this.width = Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, next))
    }
    this.apply()
  },

  endDrag() {
    if (!this.dragging) return
    this.dragging = false
    document.documentElement.style.cursor = ""
    document.documentElement.style.userSelect = ""
    window.removeEventListener("mousemove", this.onDragMove)
    window.removeEventListener("mouseup", this.onDragEnd)
    window.localStorage.setItem("sidebarRail", this.rail ? "1" : "0")
    if (!this.rail) window.localStorage.setItem("sidebarWidth", String(this.width))
  },

  toggleSidebar() {
    if (this.desktop()) {
      this.rail = !this.rail
      window.localStorage.setItem("sidebarRail", this.rail ? "1" : "0")
    } else if (this.drawerOpen) {
      this.closeDrawer()
      return
    } else {
      this.lastFocus = document.activeElement
      this.drawerOpen = true
      this.apply()
      this.focusSidebar()
      return
    }

    this.apply()
  },

  closeDrawer() {
    if (this.desktop() || !this.drawerOpen) return

    this.controls?.closeAll()
    this.drawerOpen = false
    this.apply()
    const restore = this.lastFocus || this.toggle
    this.lastFocus = null
    restore?.focus?.()
  },

  onViewportChange() {
    if (this.desktop()) {
      this.drawerOpen = false
      this.lastFocus = null
    }

    this.controls?.closeAll()
    this.apply()
  },

  onGlobalKey(event) {
    if (event.key === "Escape") {
      if (this.controls?.panels().some(panel => !panel.hidden)) return
      this.closeDrawer()
      return
    }

    if (event.key !== "Tab" || this.desktop() || !this.drawerOpen) return

    const nodes = this.focusable()
    if (nodes.length === 0) return

    const first = nodes[0]
    const last = nodes[nodes.length - 1]

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  },

  onSidebarClick(event) {
    const unpin = event.target.closest("[data-nav-unpin]")

    if (unpin && this.root?.contains(unpin)) {
      event.preventDefault()
      this.removePinnedItem(unpin.dataset.navUnpin)
      return
    }

    const pin = event.target.closest("[data-nav-pin]")

    if (pin && this.root?.contains(pin)) {
      event.preventDefault()
      this.togglePinnedItem(this.pinnedItemFromControl(pin))
      return
    }

    const tile = event.target.closest("[data-nav-tile]")
    if (tile && this.root?.contains(tile)) this.retargetTileLink(tile)

    if (!this.sidebar?.contains(event.target)) return

    const toggle = event.target.closest("[data-nav-toggle]")

    if (toggle && this.sidebar?.contains(toggle)) {
      event.preventDefault()
      this.toggleNavBranch(toggle.closest("[data-nav-branch]"))
      return
    }

    if (this.desktop() || !event.target.closest("a[href]")) return
    this.closeDrawer()
  },

  // "Open in a tile". The server renders the control as a plain link to the
  // page, which is what a narrow screen keeps: there the workspace shows one
  // tile at a time anyway. On a wide screen the click is retargeted, before
  // LiveView reads the link, to the workspace with the page the browser is on
  // in `t`, marked `inplace=1`, and the clicked page in `open`; from the
  // workspace, to its own address with `open` added. From the workspace it is
  // a patch, so the tiles on screen keep their frames; from a page it is a
  // live navigation, so the shell stays connected. The tree itself is never built here: `t` is only ever the
  // current address, and the server does the splitting.
  retargetTileLink(link) {
    const page = link.dataset.navTile
    if (!page || !this.desktop()) return

    const {pathname, search} = window.location
    const workspace = pathname === WORKSPACE || pathname.startsWith(`${WORKSPACE}/`)
    const params = workspace
      ? new URLSearchParams(search)
      : new URLSearchParams({t: leaf(pathname + search), inplace: "1"})
    params.set("open", page)

    link.setAttribute("href", `${workspace ? pathname : WORKSPACE}?${params}`)
    link.setAttribute("data-phx-link", workspace ? "patch" : "redirect")
    link.setAttribute("data-phx-link-state", "push")
  },

  toggleNavBranch(branch) {
    if (!branch) return

    const expanded = branch.dataset.navExpanded !== "true"
    this.expandedBranches[branch.dataset.navBranch] = expanded
    this.saveExpandedBranches()
    this.setNavBranch(branch, expanded)
  },

  applyNavBranches() {
    for (const branch of this.sidebar?.querySelectorAll("[data-nav-branch]") ?? []) {
      const id = branch.dataset.navBranch
      const expanded = Object.hasOwn(this.expandedBranches, id)
        ? this.expandedBranches[id]
        : branch.dataset.navDefaultExpanded === "true"

      this.setNavBranch(branch, expanded)
    }
  },

  setNavBranch(branch, expanded) {
    if (!branch) return

    branch.dataset.navExpanded = expanded ? "true" : "false"
    branch.querySelector("[data-nav-toggle]")?.setAttribute("aria-expanded", String(expanded))
    branch.querySelector(".app-nav-children")?.toggleAttribute("hidden", !expanded)
  },

  pinnedItemFromControl(pin) {
    if (pin.dataset.navPinRecord === "true") {
      return this.normalizePinnedItem({
        label: pin.dataset.navPinLabel,
        url: pin.dataset.navPinUrl,
      })
    }

    return this.normalizePinnedItem(pin.dataset.navPin)
  },

  async togglePinnedItem(item) {
    if (this.impersonating) return
    const candidate = this.migratablePinnedItem(item)
    const url = this.pinnedUrl(candidate)
    if (!candidate || !url || !this.isServedUrl(url)) return

    try {
      const response = await this.pinRequest("/api/pins/toggle", {
        method: "POST",
        body: JSON.stringify({label: candidate.label, url, icon: candidate.icon || null}),
      })
      if (!response.ok) throw new Error(`Pin update failed with status ${response.status}`)
      this.pinnedEntries = this.acceptServerPins((await response.json()).pins)
      this.renderPinnedItems()
    } catch (_error) {
      await this.fallbackPinsAfterToggle()
    }
  },

  async removePinnedItem(key) {
    if (this.impersonating) return
    const item = this.pinnedEntries.find((pinnedItem) => this.pinnedItemKey(pinnedItem) === key)
    const url = this.pinnedUrl(item)
    if (!item || !url) return

    try {
      const response = await this.pinRequest("/api/pins/toggle", {
        method: "POST",
        body: JSON.stringify({label: item.label, url, icon: item.icon || null}),
      })
      if (!response.ok) throw new Error(`Pin update failed with status ${response.status}`)
      this.pinnedEntries = this.acceptServerPins((await response.json()).pins)
      this.renderPinnedItems()
    } catch (_error) {
      await this.fallbackPinsAfterToggle()
    }
  },

  async fallbackPinsAfterToggle() {
    const pins = await this.fetchServerPins()

    if (pins) {
      this.pinnedEntries = pins
      this.renderPinnedItems()
    } else {
      this.setPinAnnouncement("Unable to update pinned pages.")
    }
  },

  navItem(id) {
    const item = document.getElementById(id)
    return this.sidebar?.contains(item) ? item : null
  },

  resolvePinnedItem(pinnedItem) {
    if (pinnedItem.navId) {
      const item = this.navItem(pinnedItem.navId)
      if (!item) return null

      return {
        key: this.pinnedItemKey(pinnedItem),
        pinnedItem,
        item,
        label: item.dataset.navLabel,
        url: item.href,
      }
    }

    if (!this.isServedUrl(pinnedItem.url)) return null

    return {
      key: this.pinnedItemKey(pinnedItem),
      pinnedItem,
      item: null,
      label: pinnedItem.label,
      url: pinnedItem.url,
    }
  },

  pinnedRow(event) {
    const target = event?.target || event
    if (!target?.closest) return null

    const row = target.closest("[data-pinned-item]")
    return this.pinnedItems?.contains(row) ? row : null
  },

  focusPinnedKey(key) {
    for (const row of this.pinnedItems?.querySelectorAll("[data-pinned-item]") ?? []) {
      if (row.dataset.pinnedItem === key) {
        row.querySelector(".app-pinned-link")?.focus()
        break
      }
    }
  },

  setPinAnnouncement(message) {
    if (this.pinnedAnnouncement) this.pinnedAnnouncement.textContent = message
  },

  startPinnedDrag(event) {
    const row = this.pinnedRow(event)

    if (!row || this.rail || !event.dataTransfer) {
      event.preventDefault()
      return
    }

    this.draggedPinnedKey = row.dataset.pinnedItem
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedPinnedKey)
    row.dataset.pinnedDragging = "true"
  },

  overPinnedDrag(event) {
    const row = this.pinnedRow(event)

    if (!row || !this.draggedPinnedKey || !event.dataTransfer) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    if (row.dataset.pinnedItem === this.draggedPinnedKey) return

    this.setPinnedDropTarget(row.dataset.pinnedItem)
  },

  dropPinnedDrag(event) {
    const row = this.pinnedRow(event)

    if (!row || !this.draggedPinnedKey) return

    event.preventDefault()

    const targetKey = row.dataset.pinnedItem
    const draggedKey = this.draggedPinnedKey

    if (targetKey !== draggedKey) {
      const reordered = this.pinnedEntries.filter(
        (pinnedItem) => this.pinnedItemKey(pinnedItem) !== draggedKey
      )
      const targetIndex = reordered.findIndex(
        (pinnedItem) => this.pinnedItemKey(pinnedItem) === targetKey
      )

      if (targetIndex >= 0) {
        const draggedItem = this.pinnedEntries.find(
          (pinnedItem) => this.pinnedItemKey(pinnedItem) === draggedKey
        )
        reordered.splice(targetIndex, 0, draggedItem)
        const previous = this.pinnedEntries
        this.pinnedEntries = reordered
        void this.reorderServerPins(reordered, false).catch(() => {
          this.pinnedEntries = previous
          this.renderPinnedItems()
          this.setPinAnnouncement("Unable to reorder pinned pages.")
        })
      }
    }

    this.endPinnedDrag()
    this.renderPinnedItems()
  },

  endPinnedDrag() {
    this.draggedPinnedKey = null
    this.dropPinnedKey = null

    for (const row of this.pinnedItems?.querySelectorAll("[data-pinned-item]") ?? []) {
      delete row.dataset.pinnedDragging
      delete row.dataset.pinnedDropTarget
    }
  },

  setPinnedDropTarget(id) {
    if (this.dropPinnedKey === id) return

    this.dropPinnedKey = id

    for (const row of this.pinnedItems?.querySelectorAll("[data-pinned-item]") ?? []) {
      if (row.dataset.pinnedItem === id) {
        row.dataset.pinnedDropTarget = "true"
      } else {
        delete row.dataset.pinnedDropTarget
      }
    }
  },

  renderPinnedItems() {
    if (!this.pinned || !this.pinnedItems) return

    const items = this.pinnedEntries.map((item) => this.resolvePinnedItem(item)).filter((item) => item)

    if (items.length !== this.pinnedEntries.length) {
      this.pinnedEntries = items.map(({pinnedItem}) => pinnedItem)
    }

    this.pinnedItems.replaceChildren()

    for (const {key, item, label: pinLabel, url} of items) {
      const row = document.createElement("div")
      row.className = "app-pinned-row group flex min-w-0 items-center"
      row.dataset.pinnedItem = key
      row.draggable = !this.rail && !this.impersonating

      const grip = document.createElement("span")
      grip.className =
        "app-pinned-grip mr-0.5 w-3 shrink-0 select-none text-center text-[0.625rem] text-muted opacity-0 transition-opacity group-hover:opacity-60"
      grip.textContent = "⠁⠁"
      grip.setAttribute("aria-hidden", "true")
      grip.title = "Drag to reorder"

      const link = document.createElement("a")
      link.href = url
      link.className =
        "app-pinned-link flex min-w-0 flex-1 items-center rounded-none px-1 py-0 text-sm font-normal text-link transition hover:bg-surface-muted hover:text-ink"

      for (const attribute of ["data-phx-link", "data-phx-link-state"]) {
        if (item?.hasAttribute(attribute)) link.setAttribute(attribute, item.getAttribute(attribute))
      }

      if (!item) {
        link.setAttribute("data-phx-link", "redirect")
        link.setAttribute("data-phx-link-state", "push")
      }

      const icon = item?.querySelector(".app-nav-icon")?.cloneNode(true)
      if (icon) link.append(icon)

      const label = document.createElement("span")
      label.className = [
        "app-nav-label app-pinned-label min-w-0 truncate",
        item && "ml-3",
      ]
        .filter(Boolean)
        .join(" ")
      label.textContent = pinLabel
      link.append(label)

      const unpin = document.createElement("button")
      unpin.type = "button"
      unpin.dataset.navUnpin = key
      unpin.disabled = this.impersonating
      unpin.title = `Unpin ${pinLabel}`
      unpin.setAttribute("aria-label", `Unpin ${pinLabel}`)
      unpin.className =
        "app-pinned-unpin grid size-4 shrink-0 place-items-center rounded-sm text-muted opacity-0 transition hover:bg-surface-muted hover:text-ink group-hover:opacity-100 focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"

      const pinIcon = item?.parentElement?.querySelector("[data-nav-pin] svg")?.cloneNode(true)
      if (pinIcon) unpin.append(pinIcon)

      // The same "Open in a tile" the row's menu entry carries; the click is
      // retargeted like any other. Ids are per pin, so two pinned rows to the
      // same page never share one.
      const tile = document.createElement("a")
      tile.href = url
      tile.id = `pinned-tile-${key.replace(/[^a-z0-9]+/gi, "-")}`
      tile.dataset.navTile = url
      tile.setAttribute("data-phx-link", "redirect")
      tile.setAttribute("data-phx-link-state", "push")
      tile.title = `Open ${pinLabel} in a tile`
      tile.setAttribute("aria-label", `Open ${pinLabel} in a tile`)
      tile.className = unpin.className.replace("app-pinned-unpin", "app-pinned-tile")
      const tileIcon = document.createElement("span")
      tileIcon.className = "hero-squares-plus size-3.5"
      tileIcon.setAttribute("aria-hidden", "true")
      tile.append(tileIcon)

      row.append(grip, link, tile, unpin)
      this.pinnedItems.append(row)
    }

    for (const pin of this.root.querySelectorAll("[data-nav-pin]")) {
      const pinnedItem = this.pinnedItemFromControl(pin)
      const key = this.pinnedItemKey(pinnedItem)
      if (!key) continue

      const url = this.pinnedUrl(pinnedItem)
      const pinned = this.pinnedEntries.some(
        (item) => url && this.pinnedUrl(item) === url
      )
      pin.disabled = this.impersonating
      pin.setAttribute("aria-disabled", String(this.impersonating))
      pin.dataset.pinned = String(pinned)
      pin.setAttribute("aria-pressed", String(pinned))
      pin.title = `${pinned ? "Unpin" : "Pin"} ${pin.getAttribute("aria-label")
        ?.replace(/^(Pin|Unpin) /, "")}`
    }

    this.pinned.hidden = items.length === 0
  },

  focusable() {
    return Array.from(this.sidebar?.querySelectorAll(FOCUSABLE) ?? []).filter(
      (node) => !node.hasAttribute("disabled") && node.offsetParent !== null
    )
  },

  focusSidebar() {
    const nodes = this.focusable()
    ;(nodes[0] || this.sidebar)?.focus?.()
  },

  apply() {
    const desktop = this.desktop()
    const open = desktop || this.drawerOpen

    this.root.dataset.sidebarMode = desktop ? "desktop" : "mobile"
    this.root.dataset.sidebarRail = this.rail ? "true" : "false"
    this.root.dataset.sidebarOpen = open ? "true" : "false"

    if (this.toggle) {
      this.toggle.setAttribute("aria-expanded", (desktop ? !this.rail : open) ? "true" : "false")
    }

    const drawerOpen = !desktop && this.drawerOpen
    const hideDrawer = !desktop && !this.drawerOpen

    if (this.sidebar) {
      this.sidebar.toggleAttribute("inert", hideDrawer)
      this.sidebar.setAttribute("aria-hidden", hideDrawer ? "true" : "false")
      this.sidebar.setAttribute("aria-modal", drawerOpen ? "true" : "false")
      this.sidebar.setAttribute("role", drawerOpen ? "dialog" : "navigation")
    }

    for (const region of [this.content, this.statusbar, this.topbarMain]) {
      if (!region) continue
      region.toggleAttribute("inert", drawerOpen)
      region.setAttribute("aria-hidden", drawerOpen ? "true" : "false")
    }

    if (this.backdrop) {
      this.backdrop.setAttribute("aria-hidden", drawerOpen ? "false" : "true")
      this.backdrop.style.pointerEvents = drawerOpen ? "auto" : "none"
    }

    this.applyNavBranches()
    this.renderPinnedItems()

    if (this.sidebar && desktop) {
      this.sidebar.style.width = `${this.rail ? RAIL_WIDTH : this.width}px`
    } else if (this.sidebar) {
      this.sidebar.style.width = ""
    }
  },
}

export default AppShell
