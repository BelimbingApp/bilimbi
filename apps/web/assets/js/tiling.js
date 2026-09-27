// The tiled workspace at /workspace. The server owns the tree, the focused
// tile and monocle, and renders one element per tile positioned by style.
// This hook owns only what the server cannot reach:
//
//   * the keyboard bridge into every frame. A keydown inside a frame never
//     reaches the parent document, so the same listener is attached to each
//     frame's document on load. The frames are same-origin, so no message
//     protocol is needed;
//   * the `Ctrl+.` tiling mode, a Hyprland submap: single-key commands with
//     Escape to leave, so nothing collides with what Windows or the browser
//     reserves. The mode names itself in the shell's `#app-mode` status
//     region and every command is also on the tile menu or a split handle;
//   * moving real focus into the tile the server has focused after a
//     keyboard move, so the ring and the caret agree;
//   * dragging a split handle. A pointer over a frame is the frame's, so
//     frames stop receiving pointer events for the length of a drag; the
//     handle follows the pointer locally and the ratio is pushed once on
//     release;
//   * reporting each frame's URL and title after it loads or navigates, and
//     the workspace area's size, which decides a split's direction.
//
// Focus follows a click, never the pointer. `DESIGN.md` "Application shell"
// and apps/base/ui/AGENTS.md carry the rest.
const LEADER_KEY = "."
const DIRECTIONS = {
  ArrowLeft: "left",
  ArrowRight: "right",
  ArrowUp: "up",
  ArrowDown: "down",
  h: "left",
  j: "down",
  k: "up",
  l: "right",
}
const MOVES = {H: "left", J: "down", K: "up", L: "right"}
const ARROWS = {ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down"}
const MODE_LABELS = {tiling: "Tiling", resize: "Resize"}
const MIN_RATIO = 0.1
const MAX_RATIO = 0.9

const Tiling = {
  mounted() {
    this.mode = "off"
    this.lastSide = "right"
    this.pendingFocus = false
    this.appliedFocus = null
    this.drag = null
    this.bound = new WeakSet()
    this.container = this.el.querySelector("#workspace-tiles")
    this.announcement = this.el.querySelector("#workspace-announcement")

    this.onKey = (event) => this.handleKey(event)
    this.onHandleKey = (event) => this.handleHandleKey(event)
    this.onPointerDown = (event) => this.startDrag(event)
    this.onPointerMove = (event) => this.moveDrag(event)
    this.onPointerUp = () => this.endDrag()
    this.onViewport = () => this.scheduleViewport()

    // Capture, so the mode sees a key before the shell's own Escape handling
    // and before any page-level binding.
    window.addEventListener("keydown", this.onKey, true)
    this.el.addEventListener("keydown", this.onHandleKey)
    this.el.addEventListener("pointerdown", this.onPointerDown)
    window.addEventListener("resize", this.onViewport)

    this.bindFrames()
    this.reportViewport()
  },

  updated() {
    // A patch morphs this element's attributes back to what the server
    // rendered; the mode is the hook's, so it goes back on.
    this.el.dataset.mode = this.mode
    this.bindFrames()
    this.applyFocus()
  },

  destroyed() {
    this.setMode("off")
    window.removeEventListener("keydown", this.onKey, true)
    this.el.removeEventListener("keydown", this.onHandleKey)
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    window.removeEventListener("resize", this.onViewport)
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    if (this.viewportFrame) cancelAnimationFrame(this.viewportFrame)
  },

  // ---------------------------------------------------------------
  // Frames
  // ---------------------------------------------------------------

  frames() {
    return [...this.el.querySelectorAll("iframe[data-tile-frame]")]
  },

  bindFrames() {
    for (const frame of this.frames()) {
      if (this.bound.has(frame)) continue
      this.bound.add(frame)
      frame.addEventListener("load", () => this.attachFrame(frame))
      if (this.frameReady(frame)) this.attachFrame(frame)
    }
  },

  frameReady(frame) {
    try {
      const doc = frame.contentDocument
      return Boolean(doc && doc.readyState === "complete" && doc.location?.pathname !== "blank")
    } catch {
      return false
    }
  },

  // Every load is a new document, so the listeners go on again; the old
  // document took its own away.
  attachFrame(frame) {
    const win = frame.contentWindow
    const doc = frame.contentDocument
    if (!win || !doc) return

    const id = frame.dataset.tileFrame
    doc.addEventListener("keydown", this.onKey, true)
    doc.addEventListener("focusin", () => this.focusTile(id))
    doc.addEventListener("pointerdown", () => this.focusTile(id))
    win.addEventListener("phx:page-loading-stop", () => this.report(frame))
    this.report(frame)
  },

  report(frame) {
    const win = frame.contentWindow
    const doc = frame.contentDocument
    if (!win?.location || !doc) return

    this.pushEvent("tile-navigated", {
      id: frame.dataset.tileFrame,
      path: win.location.pathname + win.location.search,
      title: doc.title,
    })
  },

  focusTile(id) {
    if (this.el.dataset.focused === id) return
    this.pushEvent("focus-tile", {id})
  },

  // After a keyboard move the server has a new focused tile; put real focus
  // there so the next key lands in it.
  applyFocus() {
    const focused = this.el.dataset.focused
    if (!this.pendingFocus || !focused || focused === this.appliedFocus) return

    this.pendingFocus = false
    this.appliedFocus = focused

    const frame = this.el.querySelector(`iframe[data-tile-frame="${focused}"]`)
    if (frame) {
      frame.focus()
      frame.contentWindow?.focus?.()
    } else {
      document.getElementById(`tile-${focused}-header-title`)?.focus()
    }
  },

  // ---------------------------------------------------------------
  // Keyboard mode
  // ---------------------------------------------------------------

  handleKey(event) {
    if (this.leader(event)) {
      event.preventDefault()
      event.stopPropagation()
      this.setMode(this.mode === "off" ? "tiling" : "off")
      return
    }

    if (this.mode === "off") return

    if (event.key === "Escape") {
      // An open menu or panel takes Escape first, as everywhere in the shell.
      if (this.openDisclosure()) return
      event.preventDefault()
      event.stopPropagation()
      this.setMode(this.mode === "resize" ? "tiling" : "off")
      return
    }

    if (event.ctrlKey || event.altKey || event.metaKey) return

    const handled =
      this.mode === "resize" ? this.resizeKey(event) : this.tilingKey(event)

    if (handled) {
      event.preventDefault()
      event.stopPropagation()
    }
  },

  leader(event) {
    return event.key === LEADER_KEY && event.ctrlKey && !event.altKey && !event.metaKey && !event.shiftKey
  },

  tilingKey(event) {
    const focused = this.el.dataset.focused || null
    const side = event.shiftKey ? null : DIRECTIONS[event.key]

    if (side) {
      this.lastSide = side
      this.expectFocus()
      this.pushEvent("focus-direction", {side})
      return true
    }

    const move = MOVES[event.key]
    if (move) {
      if (focused) {
        this.expectFocus()
        this.pushEvent("move-tile", {id: focused, side: move})
      }
      return true
    }

    if (/^[1-9]$/.test(event.key)) {
      this.pushEvent("open-layout", {n: Number(event.key)})
      return true
    }

    switch (event.key) {
      case "s":
        if (focused) this.pushEvent("swap-tile", {id: focused, side: this.lastSide})
        return true
      case "r":
        this.setMode("resize")
        return true
      case "f":
        if (focused) this.pushEvent("toggle-monocle", {id: focused})
        return true
      case "t":
        if (focused) this.pushEvent("toggle-split", {id: focused})
        return true
      case "n":
        this.openPicker()
        return true
      case "q":
        if (focused) {
          this.expectFocus()
          this.pushEvent("close-tile", {id: focused})
        }
        return true
      default:
        return false
    }
  },

  resizeKey(event) {
    const side = DIRECTIONS[event.key]
    if (!side || !this.el.dataset.focused) return false
    this.pushEvent("resize-step", {side})
    return true
  },

  // The picker is a dialog the person types into, so the mode ends first.
  openPicker() {
    const count = Number(this.el.dataset.tileCount || 0)
    const max = Number(this.el.dataset.maxTiles || 0)

    if (max && count >= max) {
      this.announce(`The workspace holds ${max} tiles at most. Close one to open another page.`)
      return
    }

    this.setMode("off")
    this.pushEvent("open-picker", {})
  },

  expectFocus() {
    this.pendingFocus = true
    this.appliedFocus = null
  },

  setMode(mode) {
    this.mode = mode
    this.el.dataset.mode = mode

    const target = document.getElementById("app-mode")
    if (!target) return

    if (mode === "off") {
      target.hidden = true
      target.textContent = ""
    } else {
      target.textContent = MODE_LABELS[mode]
      target.hidden = false
    }
  },

  // An open menu or panel: the account and display panels, a tile menu. The
  // sidebar toggle and an expanded sidebar branch also say `aria-expanded`,
  // and Escape has never collapsed either on a wide screen, so they do not
  // count.
  openDisclosure() {
    return Boolean(
      document.querySelector(
        '#app-shell [aria-expanded="true"]:not([data-nav-toggle]):not(#app-sidebar-toggle)'
      )
    )
  },

  announce(message) {
    if (this.announcement) this.announcement.textContent = message
  },

  // ---------------------------------------------------------------
  // Split handles
  // ---------------------------------------------------------------

  handleHandleKey(event) {
    const handle = event.target.closest?.("[data-split]")
    const side = ARROWS[event.key]
    if (!handle || !side) return

    event.preventDefault()
    this.pushEvent("nudge-split", {id: handle.dataset.split, side})
  },

  startDrag(event) {
    const handle = event.target.closest?.("[data-split]")
    if (!handle || event.button !== 0 || !this.container) return

    event.preventDefault()
    const [x, y, w, h] = (handle.dataset.rect || "0 0 1 1").split(" ").map(Number)

    this.drag = {
      handle,
      id: handle.dataset.split,
      direction: handle.dataset.direction,
      area: this.container.getBoundingClientRect(),
      split: {x, y, w, h},
      ratio: null,
    }

    for (const frame of this.frames()) frame.style.pointerEvents = "none"
    document.documentElement.style.cursor = this.drag.direction === "h" ? "col-resize" : "row-resize"
    document.documentElement.style.userSelect = "none"
    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
  },

  moveDrag(event) {
    if (!this.drag) return
    const {handle, direction, area, split} = this.drag

    let ratio
    if (direction === "h") {
      const fraction = (event.clientX - area.left) / area.width
      ratio = (fraction - split.x) / split.w
    } else {
      const fraction = (event.clientY - area.top) / area.height
      ratio = (fraction - split.y) / split.h
    }

    ratio = Math.min(MAX_RATIO, Math.max(MIN_RATIO, ratio))
    this.drag.ratio = ratio

    if (direction === "h") {
      handle.style.left = `${(split.x + split.w * ratio) * 100}%`
    } else {
      handle.style.top = `${(split.y + split.h * ratio) * 100}%`
    }
  },

  endDrag() {
    if (!this.drag) return
    const {id, ratio} = this.drag
    this.drag = null

    for (const frame of this.frames()) frame.style.pointerEvents = ""
    document.documentElement.style.cursor = ""
    document.documentElement.style.userSelect = ""
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)

    if (ratio !== null) this.pushEvent("resize-split", {id, ratio: Number(ratio.toFixed(3))})
  },

  // ---------------------------------------------------------------
  // Viewport
  // ---------------------------------------------------------------

  scheduleViewport() {
    if (this.viewportFrame) return
    this.viewportFrame = requestAnimationFrame(() => {
      this.viewportFrame = null
      this.reportViewport()
    })
  },

  reportViewport() {
    if (!this.container) return
    const rect = this.container.getBoundingClientRect()
    if (rect.width <= 0 || rect.height <= 0) return
    this.pushEvent("viewport", {w: Math.round(rect.width), h: Math.round(rect.height)})
  },
}

export default Tiling
