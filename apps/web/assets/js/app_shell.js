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
    this.pinnedEntries = this.readPinnedItems()
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
    this.apply()
  },

  updated() {
    this.apply()
  },

  destroyed() {
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

  readPinnedItems() {
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

  savePinnedItems() {
    window.localStorage.setItem(PINNED_STORAGE, JSON.stringify(this.pinnedEntries))
  },

  normalizePinnedItem(item) {
    if (typeof item === "string") {
      const id = item.trim()
      return id ? {id} : null
    }

    if (!item || typeof item !== "object" || Array.isArray(item)) return null

    const id = typeof item.id === "string" ? item.id.trim() : ""
    if (id) return {id}

    const label = typeof item.label === "string" ? item.label.trim() : ""
    const url = this.normalizePinnedUrl(item.url)

    return label && url ? {label, url} : null
  },

  normalizePinnedUrl(url) {
    if (typeof url !== "string") return null

    try {
      const parsed = new URL(url, window.location.origin)
      if (parsed.origin !== window.location.origin) return null

      return `${parsed.pathname}${parsed.search}${parsed.hash}`
    } catch {
      return null
    }
  },

  pinnedItemKey(item) {
    if (item?.id) return `nav:${item.id}`
    if (item?.url) return `url:${item.url}`
    return null
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

  togglePinnedItem(item) {
    const key = this.pinnedItemKey(item)
    if (!key) return

    if (this.pinnedEntries.some((pinnedItem) => this.pinnedItemKey(pinnedItem) === key)) {
      this.pinnedEntries = this.pinnedEntries.filter(
        (pinnedItem) => this.pinnedItemKey(pinnedItem) !== key
      )
    } else {
      this.pinnedEntries.push(item)
    }

    this.savePinnedItems()
    this.renderPinnedItems()
  },

  removePinnedItem(key) {
    if (!key) return

    this.pinnedEntries = this.pinnedEntries.filter(
      (pinnedItem) => this.pinnedItemKey(pinnedItem) !== key
    )
    this.savePinnedItems()
    this.renderPinnedItems()
  },

  navItem(id) {
    const item = document.getElementById(id)
    return this.sidebar?.contains(item) ? item : null
  },

  resolvePinnedItem(pinnedItem) {
    if (pinnedItem.id) {
      const item = this.navItem(pinnedItem.id)
      if (!item) return null

      return {
        key: this.pinnedItemKey(pinnedItem),
        pinnedItem,
        item,
        label: item.dataset.navLabel,
        url: item.href,
      }
    }

    return {
      key: this.pinnedItemKey(pinnedItem),
      pinnedItem,
      item: null,
      label: pinnedItem.label,
      url: pinnedItem.url,
    }
  },

  pinnedRow(event) {
    if (!(event.target instanceof Element)) return null

    const row = event.target.closest("[data-pinned-item]")
    return this.pinnedItems?.contains(row) ? row : null
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
        this.pinnedEntries = reordered
        this.savePinnedItems()
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
      this.savePinnedItems()
    }

    this.pinnedItems.replaceChildren()

    for (const {key, item, label: pinLabel, url} of items) {
      const row = document.createElement("div")
      row.className = "app-pinned-row group flex min-w-0 items-center"
      row.dataset.pinnedItem = key
      row.draggable = !this.rail

      const grip = document.createElement("span")
      grip.className =
        "app-pinned-grip mr-0.5 w-3 shrink-0 select-none text-center text-[0.625rem] text-muted opacity-0 transition-opacity group-hover:opacity-60"
      grip.textContent = "⠁⠁"
      grip.setAttribute("aria-hidden", "true")
      grip.title = "Drag to reorder"

      const link = document.createElement("a")
      link.href = url
      link.className =
        "app-pinned-link flex min-w-0 flex-1 items-center rounded-none px-1 py-px text-sm font-normal text-link transition hover:bg-surface-muted hover:text-ink"

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
      unpin.title = `Unpin ${pinLabel}`
      unpin.setAttribute("aria-label", `Unpin ${pinLabel}`)
      unpin.className =
        "app-pinned-unpin grid size-4 shrink-0 place-items-center rounded-sm text-muted opacity-0 transition hover:bg-surface-muted hover:text-ink group-hover:opacity-100 focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"

      const pinIcon = item?.parentElement?.querySelector("[data-nav-pin] svg")?.cloneNode(true)
      if (pinIcon) unpin.append(pinIcon)

      row.append(grip, link, unpin)
      this.pinnedItems.append(row)
    }

    for (const pin of this.root.querySelectorAll("[data-nav-pin]")) {
      const pinnedItem = this.pinnedItemFromControl(pin)
      const key = this.pinnedItemKey(pinnedItem)
      if (!key) continue

      const pinned = this.pinnedEntries.some(
        (item) => this.pinnedItemKey(item) === key
      )
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
