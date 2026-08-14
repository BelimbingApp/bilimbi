// Authenticated shell chrome. Owns only what the server cannot: the desktop
// rail choice (localStorage), the mobile drawer, Escape/backdrop close, and
// returning focus to the toggle. Navigation, capabilities, and status values
// stay server-rendered.
const DESKTOP = "(min-width: 1024px)"
const FOCUSABLE =
  'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'

const AppShell = {
  mounted() {
    this.root = this.el
    this.toggle = this.el.querySelector("#app-sidebar-toggle")
    this.sidebar = this.el.querySelector("#app-sidebar")
    this.backdrop = this.el.querySelector("#app-sidebar-backdrop")
    this.mq = window.matchMedia(DESKTOP)
    this.rail = window.localStorage.getItem("sidebarRail") === "1"
    this.drawerOpen = false
    this.lastFocus = null

    this.onToggle = () => this.toggleSidebar()
    this.onBackdrop = () => this.closeDrawer()
    this.onKey = (event) => this.onGlobalKey(event)
    this.onMq = () => this.onViewportChange()
    this.onNav = (event) => this.onSidebarClick(event)

    this.toggle?.addEventListener("click", this.onToggle)
    this.backdrop?.addEventListener("click", this.onBackdrop)
    this.sidebar?.addEventListener("click", this.onNav)
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
    window.removeEventListener("keydown", this.onKey)
    this.mq?.removeEventListener("change", this.onMq)
  },

  desktop() {
    return this.mq.matches
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

    if (this.backdrop) {
      const showBackdrop = open && !desktop
      this.backdrop.setAttribute("aria-hidden", showBackdrop ? "false" : "true")
      this.backdrop.style.pointerEvents = showBackdrop ? "auto" : "none"
    }
  },
}

export default AppShell
