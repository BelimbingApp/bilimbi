// Authenticated shell chrome. Owns only what the server cannot: the desktop
// rail choice (localStorage), the mobile drawer, Escape/backdrop close, and
// returning focus to the toggle. Navigation, capabilities, and status values
// stay server-rendered.
const DESKTOP = "(min-width: 1024px)"
const RAIL_WIDTH = 56
const MIN_WIDTH = 180
const MAX_WIDTH = 360
const DEFAULT_WIDTH = 240
const NAV_EXPANSION_STORAGE = "sidebarExpandedBranches"
const PINNED_STORAGE = "sidebarPinnedItems"
const FOCUSABLE =
  'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'

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
    this.mq = window.matchMedia(DESKTOP)
    this.rail = window.localStorage.getItem("sidebarRail") === "1"
    this.width = this.readWidth()
    this.expandedBranches = this.readExpandedBranches()
    this.pinnedItemIds = this.readPinnedItemIds()
    this.drawerOpen = false
    this.lastFocus = null
    this.dragging = false

    this.onToggle = () => this.toggleSidebar()
    this.onBackdrop = () => this.closeDrawer()
    this.onKey = (event) => this.onGlobalKey(event)
    this.onMq = () => this.onViewportChange()
    this.onNav = (event) => this.onSidebarClick(event)
    this.onDragStart = (event) => this.startDrag(event)
    this.onDragMove = (event) => this.moveDrag(event)
    this.onDragEnd = () => this.endDrag()

    this.toggle?.addEventListener("click", this.onToggle)
    this.backdrop?.addEventListener("click", this.onBackdrop)
    this.sidebar?.addEventListener("click", this.onNav)
    this.drag?.addEventListener("mousedown", this.onDragStart)
    window.addEventListener("keydown", this.onKey)
    this.mq.addEventListener("change", this.onMq)
    this.apply()
  },

  updated() {
    this.apply()
  },

  destroyed() {
    this.toggle?.removeEventListener("click", this.onToggle)
    this.backdrop?.removeEventListener("click", this.onBackdrop)
    this.sidebar?.removeEventListener("click", this.onNav)
    this.drag?.removeEventListener("mousedown", this.onDragStart)
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

  readPinnedItemIds() {
    try {
      const stored = JSON.parse(window.localStorage.getItem(PINNED_STORAGE) ?? "[]")

      return Array.isArray(stored)
        ? [...new Set(stored.filter((id) => typeof id === "string"))]
        : []
    } catch {
      return []
    }
  },

  savePinnedItemIds() {
    window.localStorage.setItem(PINNED_STORAGE, JSON.stringify(this.pinnedItemIds))
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

    this.apply()
  },

  onGlobalKey(event) {
    if (event.key === "Escape") {
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
    const pin = event.target.closest("[data-nav-pin]")

    if (pin && this.sidebar?.contains(pin)) {
      event.preventDefault()
      this.togglePinnedItem(pin.dataset.navPin)
      return
    }

    const toggle = event.target.closest("[data-nav-toggle]")

    if (toggle && this.sidebar?.contains(toggle)) {
      event.preventDefault()
      this.toggleNavBranch(toggle.closest("[data-nav-branch]"))
      return
    }

    if (this.desktop() || !event.target.closest("a[href]")) return
    this.closeDrawer()
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

  togglePinnedItem(id) {
    if (!id) return

    if (this.pinnedItemIds.includes(id)) {
      this.pinnedItemIds = this.pinnedItemIds.filter((itemId) => itemId !== id)
    } else {
      this.pinnedItemIds.push(id)
    }

    this.savePinnedItemIds()
    this.renderPinnedItems()
  },

  navItem(id) {
    const item = document.getElementById(id)
    return this.sidebar?.contains(item) ? item : null
  },

  renderPinnedItems() {
    if (!this.pinned || !this.pinnedItems) return

    const items = this.pinnedItemIds
      .map((id) => ({id, item: this.navItem(id)}))
      .filter(({item}) => item)

    if (items.length !== this.pinnedItemIds.length) {
      this.pinnedItemIds = items.map(({id}) => id)
      this.savePinnedItemIds()
    }

    this.pinnedItems.replaceChildren()

    for (const {id, item} of items) {
      const row = document.createElement("div")
      row.className = "app-pinned-row group flex min-w-0 items-center"

      const link = document.createElement("a")
      link.href = item.href
      link.className =
        "app-pinned-link flex min-w-0 flex-1 items-center gap-1 rounded-none px-1 py-px text-sm text-ink-muted transition hover:bg-surface-sunken hover:text-ink"

      for (const attribute of ["data-phx-link", "data-phx-link-state"]) {
        if (item.hasAttribute(attribute)) link.setAttribute(attribute, item.getAttribute(attribute))
      }

      const icon = item.querySelector(".app-nav-icon")?.cloneNode(true)
      if (icon) link.append(icon)

      const label = document.createElement("span")
      label.className = "app-nav-label app-pinned-label ml-3 min-w-0 truncate"
      label.textContent = item.dataset.navLabel
      link.append(label)

      const unpin = document.createElement("button")
      unpin.type = "button"
      unpin.dataset.navPin = id
      unpin.title = `Unpin ${item.dataset.navLabel}`
      unpin.setAttribute("aria-label", `Unpin ${item.dataset.navLabel}`)
      unpin.className =
        "app-pinned-unpin grid size-4 shrink-0 place-items-center rounded-sm text-ink-faint opacity-0 transition hover:bg-surface hover:text-ink group-hover:opacity-100 focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"

      const pinIcon = item.parentElement?.querySelector("[data-nav-pin] svg")?.cloneNode(true)
      if (pinIcon) unpin.append(pinIcon)

      row.append(link, unpin)
      this.pinnedItems.append(row)
    }

    for (const pin of this.sidebar.querySelectorAll("[data-nav-pin]")) {
      const pinned = this.pinnedItemIds.includes(pin.dataset.navPin)
      pin.dataset.pinned = String(pinned)
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
      this.toggle.setAttribute("aria-expanded", open ? "true" : "false")
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
