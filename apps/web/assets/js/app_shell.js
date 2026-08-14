// Authenticated shell chrome. Owns only what the server cannot: the desktop
// rail choice (localStorage), the mobile drawer, Escape/backdrop close, and
// returning focus to the toggle. Navigation, capabilities, and status values
// stay server-rendered.
const DESKTOP = "(min-width: 1024px)"
const RAIL_WIDTH = 56
const MIN_WIDTH = 180
const MAX_WIDTH = 360
const DEFAULT_WIDTH = 240
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
    this.mq = window.matchMedia(DESKTOP)
    this.rail = window.localStorage.getItem("sidebarRail") === "1"
    this.width = this.readWidth()
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
    if (this.desktop() || !event.target.closest("a[href]")) return
    this.closeDrawer()
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

    if (this.sidebar && desktop) {
      this.sidebar.style.width = `${this.rail ? RAIL_WIDTH : this.width}px`
    } else if (this.sidebar) {
      this.sidebar.style.width = ""
    }
  },
}

export default AppShell
