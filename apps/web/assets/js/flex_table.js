// FlexTable: the browser half of `Bilimbi.Base.UI.Components.flex_table/1`.
//
// The server renders the toolbar, the full table and one canvas host; this
// hook owns what only a browser can do: dragging a chip or a heading to
// reorder or to group, Ctrl+wheel to zoom, the canvas drawing for the
// compact and carpet modes from windows the server pushes, the hover
// tooltip, the drag-a-rectangle zoom, and the bar widths the CSP refuses
// to take from a style attribute. Every state change is pushed to the host
// as the one `data-event` with an `op`; nothing here is the source of truth.
//
// Windows: in a canvas mode the host pushes `"<id>:window"` with
// `{offset, rows: [[key, [[text, n, band, scale], ...]], ...], total}`.
// The hook keeps the latest window, asks for another when the viewport
// scrolls out of it, and draws only the rows and columns on screen.

const OVERSCAN = 0.5
const ZOOM_THROTTLE_MS = 120
const HOVER_DEBOUNCE_MS = 80

const FlexTable = {
  mounted() {
    this.rows = new Map()
    this.total = 0
    this.hoverTimer = null
    this.lastZoomAt = 0
    this.drag = null
    this.rect = null
    this.readDataset()

    this.onDragStart = (event) => this.dragStart(event)
    this.onDragOver = (event) => this.dragOver(event)
    this.onDragLeave = (event) => this.dragLeave(event)
    this.onDrop = (event) => this.drop(event)
    this.onDragEnd = () => this.dragEnd()
    this.onWheel = (event) => this.wheel(event)
    this.onKeyDown = (event) => this.keydown(event)
    this.onScroll = () => this.scrolled()
    this.onMouseMove = (event) => this.hover(event)
    this.onMouseLeave = () => this.hideTooltip()
    this.onMouseDown = (event) => this.rectStart(event)
    this.onMouseUp = (event) => this.rectEnd(event)
    this.onResize = () => this.layout()

    this.el.addEventListener("dragstart", this.onDragStart)
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("dragleave", this.onDragLeave)
    this.el.addEventListener("drop", this.onDrop)
    this.el.addEventListener("dragend", this.onDragEnd)
    this.el.addEventListener("keydown", this.onKeyDown)
    this.viewport().addEventListener("wheel", this.onWheel, {passive: false})
    this.viewport().addEventListener("scroll", this.onScroll)
    window.addEventListener("resize", this.onResize)

    this.handleEvent(`${this.el.id}:window`, (payload) => this.receiveWindow(payload))
    this.handleEvent(`${this.el.id}:scroll`, ({row, col}) => this.scrollTo(row, col))

    this.bindCanvas()
    this.applyBars()
    this.layout()
    if (this.canvasMode()) this.requestWindow()
  },

  updated() {
    const before = {mode: this.mode, zoom: this.zoom, columns: this.columnsJson}
    this.readDataset()
    this.applyBars()
    this.bindCanvas()
    if (before.mode !== this.mode || before.zoom !== this.zoom || before.columns !== this.columnsJson) {
      this.rows.clear()
      this.layout()
      if (this.canvasMode()) this.requestWindow()
    } else {
      this.layout()
    }
  },

  destroyed() {
    this.el.removeEventListener("dragstart", this.onDragStart)
    this.el.removeEventListener("dragover", this.onDragOver)
    this.el.removeEventListener("dragleave", this.onDragLeave)
    this.el.removeEventListener("drop", this.onDrop)
    this.el.removeEventListener("dragend", this.onDragEnd)
    this.el.removeEventListener("keydown", this.onKeyDown)
    const viewport = this.viewport()
    if (viewport) {
      viewport.removeEventListener("wheel", this.onWheel)
      viewport.removeEventListener("scroll", this.onScroll)
    }
    window.removeEventListener("resize", this.onResize)
    this.unbindCanvas()
    clearTimeout(this.hoverTimer)
  },

  // --- dataset -----------------------------------------------------------

  readDataset() {
    const data = this.el.dataset
    this.event = data.event
    this.target = data.target || null
    this.zoom = parseInt(data.zoom, 10) || 28
    this.mode = data.mode
    this.columnsJson = data.columns
    this.columns = JSON.parse(data.columns || "[]")
    this.total = parseInt(data.total, 10) || 0
    this.offset = parseInt(data.offset, 10) || 0
  },

  canvasMode() {
    return this.mode === "carpet" || this.mode === "mid"
  },

  viewport() {
    return this.el.querySelector("[data-viewport]")
  },

  push(payload, reply) {
    if (this.target) this.pushEventTo(this.target, this.event, payload, reply)
    else this.pushEvent(this.event, payload, reply)
  },

  // --- bars (CSSOM, because the CSP refuses inline style) ---------------

  applyBars() {
    for (const bar of this.el.querySelectorAll("[data-bar]")) {
      const percent = parseFloat(bar.dataset.bar)
      bar.style.width = Number.isFinite(percent) ? `${percent}%` : "0%"
    }
  },

  // --- drag to reorder or to group --------------------------------------

  dragStart(event) {
    const source = event.target.closest("[data-chip], [data-header]")
    if (!source) return
    this.drag = {spec: source.dataset.chip || source.dataset.header, kind: source.dataset.chip ? "chip" : "header"}
    source.dataset.dragging = "true"
    this.el.dataset.dragActive = "true"
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.drag.spec)
  },

  dragOver(event) {
    if (!this.drag) return
    const zone = event.target.closest("[data-group-zone], [data-pivot-zone]")
    const over = event.target.closest("[data-chip], [data-header]")
    if (!zone && !over) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.clearDropMarks()
    if (zone) {
      zone.dataset.drop = zone.hasAttribute("data-pivot-zone") ? "pivot" : "group"
    } else if (over) {
      const spec = over.dataset.chip || over.dataset.header
      if (spec !== this.drag.spec) over.dataset.drop = this.before(event, over) ? "before" : "after"
    }
  },

  dragLeave(event) {
    const left = event.target.closest && event.target.closest("[data-chip], [data-header], [data-group-zone], [data-pivot-zone]")
    if (left) delete left.dataset.drop
  },

  drop(event) {
    if (!this.drag) return
    event.preventDefault()
    const zone = event.target.closest("[data-group-zone], [data-pivot-zone]")
    const over = event.target.closest("[data-chip], [data-header]")
    const spec = this.drag.spec
    if (zone) {
      this.push({op: zone.hasAttribute("data-pivot-zone") ? "pivot" : "group", spec})
    } else if (over) {
      const target = over.dataset.chip || over.dataset.header
      if (target !== spec) {
        const before = this.before(event, over)
        this.push({op: "move", spec, before: before ? target : this.after(target)})
      }
    }
    this.dragEnd()
  },

  // The spec following `target` in the current order, or null at the end.
  after(target) {
    const specs = this.columns.map((column) => column.spec)
    const index = specs.indexOf(target)
    return index >= 0 && index + 1 < specs.length ? specs[index + 1] : null
  },

  before(event, element) {
    const box = element.getBoundingClientRect()
    return event.clientX < box.left + box.width / 2
  },

  dragEnd() {
    this.clearDropMarks()
    for (const el of this.el.querySelectorAll("[data-dragging]")) delete el.dataset.dragging
    delete this.el.dataset.dragActive
    this.drag = null
  },

  clearDropMarks() {
    for (const el of this.el.querySelectorAll("[data-drop]")) delete el.dataset.drop
  },

  // --- zoom ------------------------------------------------------------

  wheel(event) {
    if (!event.ctrlKey && !event.metaKey) return
    event.preventDefault()
    const now = Date.now()
    if (now - this.lastZoomAt < ZOOM_THROTTLE_MS) return
    this.lastZoomAt = now
    this.push({op: "zoom", dir: event.deltaY < 0 ? "in" : "out"})
  },

  keydown(event) {
    if (event.target.closest("input, textarea, select, button, [role=menu]")) {
      return this.addBarKeys(event)
    }
    if (event.key === "+" || event.key === "=") {
      event.preventDefault()
      this.push({op: "zoom", dir: "in"})
    } else if (event.key === "-") {
      event.preventDefault()
      this.push({op: "zoom", dir: "out"})
    }
  },

  // In the add bar, the arrow keys walk the suggestions and Enter picks the
  // focused one; Escape clears what was typed.
  addBarKeys(event) {
    const input = event.target.closest("input[name=add]")
    const option = event.target.closest("[role=listbox] button")
    if (!input && !option) return
    const options = [...this.el.querySelectorAll("[role=listbox] button")]
    const index = options.indexOf(document.activeElement)
    if (event.key === "ArrowDown" && options.length) {
      event.preventDefault()
      options[Math.min(index + 1, options.length - 1)].focus()
    } else if (event.key === "ArrowUp" && options.length) {
      event.preventDefault()
      if (index <= 0) this.el.querySelector("input[name=add]").focus()
      else options[index - 1].focus()
    } else if (event.key === "Escape" && input) {
      event.preventDefault()
      input.value = ""
      input.dispatchEvent(new Event("input", {bubbles: true}))
    }
  },

  // --- canvas ------------------------------------------------------------

  bindCanvas() {
    const canvas = this.el.querySelector("canvas")
    if (canvas === this.canvas) return
    this.unbindCanvas()
    this.canvas = canvas
    if (!canvas) return
    canvas.addEventListener("mousemove", this.onMouseMove)
    canvas.addEventListener("mouseleave", this.onMouseLeave)
    canvas.addEventListener("mousedown", this.onMouseDown)
    canvas.addEventListener("mouseup", this.onMouseUp)
  },

  unbindCanvas() {
    if (!this.canvas) return
    this.canvas.removeEventListener("mousemove", this.onMouseMove)
    this.canvas.removeEventListener("mouseleave", this.onMouseLeave)
    this.canvas.removeEventListener("mousedown", this.onMouseDown)
    this.canvas.removeEventListener("mouseup", this.onMouseUp)
    this.canvas = null
  },

  cellWidth() {
    if (this.mode === "carpet") return this.zoom
    return this.zoom * 6
  },

  // The compact view keeps a heading band above the rows; the carpet has
  // no room for one and reads through the chips and the hover.
  headerHeight() {
    return this.mode === "mid" ? this.zoom + 6 : 0
  },

  // The scroll height is the whole set's; the canvas is only as tall as the
  // viewport and is redrawn from the scroll position.
  layout() {
    const host = this.el.querySelector("[data-canvas-host]")
    const viewport = this.viewport()
    if (!host || !this.canvas || !viewport) return
    const rowHeight = this.zoom
    const width = Math.max(this.columns.length * this.cellWidth(), 1)
    host.style.height = `${Math.max(this.total * rowHeight, rowHeight) + this.headerHeight()}px`
    host.style.width = `${width}px`
    const viewHeight = Math.min(viewport.clientHeight || 600, 4000)
    const viewWidth = Math.min(Math.max(viewport.clientWidth, width), 8000)
    const ratio = window.devicePixelRatio || 1
    this.canvas.width = Math.floor(viewWidth * ratio)
    this.canvas.height = Math.floor(viewHeight * ratio)
    this.canvas.style.width = `${viewWidth}px`
    this.canvas.style.height = `${viewHeight}px`
    this.draw()
  },

  visibleRange() {
    const viewport = this.viewport()
    const rowHeight = this.zoom
    const first = Math.max(Math.floor(viewport.scrollTop / rowHeight), 0)
    const count = Math.ceil((viewport.clientHeight || 600) / rowHeight) + 1
    return {first, last: Math.min(first + count, this.total)}
  },

  scrolled() {
    if (!this.canvasMode()) return
    this.draw()
    const {first, last} = this.visibleRange()
    if (!this.covers(first, last)) this.requestWindow()
  },

  covers(first, last) {
    for (let index = first; index < last; index++) if (!this.rows.has(index)) return false
    return true
  },

  requestWindow() {
    if (!this.viewport()) return
    const {first, last} = this.visibleRange()
    const span = Math.max(last - first, 1)
    const offset = Math.max(first - Math.floor(span * OVERSCAN), 0)
    const limit = Math.min(Math.ceil(span * (1 + 2 * OVERSCAN)), 5000)
    if (this.pending && this.pending.offset === offset && this.pending.limit === limit) return
    this.pending = {offset, limit}
    this.push({op: "window", id: this.el.id, offset, limit, detail: this.mode === "carpet" ? "levels" : "text"})
  },

  scrollTo(row, col) {
    const viewport = this.viewport()
    if (!viewport) return
    viewport.scrollTop = Math.max((row || 0) * this.zoom, 0)
    viewport.scrollLeft = Math.max((col || 0) * this.cellWidth(), 0)
    this.scrolled()
  },

  receiveWindow(payload) {
    this.pending = null
    this.total = payload.total
    this.rows.clear()
    payload.rows.forEach((row, index) => this.rows.set(payload.offset + index, row))
    this.layout()
  },

  colours() {
    const style = getComputedStyle(document.documentElement)
    const read = (name) => style.getPropertyValue(name).trim()
    return {
      scale: [1, 2, 3, 4, 5].map((n) => read(`--color-scale-${n}`)),
      cat: [1, 2, 3, 4, 5, 6, 7, 8].map((n) => read(`--color-cat-${n}`)),
      empty: read("--color-surface-sunken"),
      line: read("--color-low-contrast-line"),
      ink: read("--color-ink"),
      surface: read("--color-surface"),
    }
  },

  cellColour(cell, colours) {
    if (!cell || cell[2] === null || cell[2] === undefined) return colours.empty
    const [, , band, scale] = cell
    if (scale === "categorical") return colours.cat[band % 8]
    if (scale === "binary") return band > 0 ? colours.scale[3] : colours.empty
    return colours.scale[Math.min(band, 4)]
  },

  draw() {
    if (!this.canvas || !this.canvasMode()) return
    const context = this.canvas.getContext("2d")
    if (!context) return
    const ratio = window.devicePixelRatio || 1
    context.setTransform(ratio, 0, 0, ratio, 0, 0)
    const viewport = this.viewport()
    const rowHeight = this.zoom
    const cellWidth = this.cellWidth()
    const colours = this.colours()
    const width = this.canvas.width / ratio
    const height = this.canvas.height / ratio
    context.fillStyle = colours.surface
    context.fillRect(0, 0, width, height)
    const {first, last} = this.visibleRange()
    const top = viewport.scrollTop
    const gap = rowHeight >= 4 ? 1 : 0
    const mid = this.mode === "mid"
    const headerHeight = this.headerHeight()
    if (mid) context.font = `${Math.max(Math.floor(rowHeight * 0.62), 8)}px ${getComputedStyle(this.el).fontFamily}`
    for (let index = first; index < last; index++) {
      const row = this.rows.get(index)
      const y = index * rowHeight - top + headerHeight
      this.columns.forEach((column, c) => {
        const x = c * cellWidth
        const cell = row ? row[1][c] : null
        const lens = column.lens
        if (!row) {
          context.fillStyle = colours.empty
          context.fillRect(x, y, cellWidth - gap, rowHeight - gap)
          return
        }
        if (mid && (lens === "value" || lens === "trend")) {
          context.fillStyle = colours.surface
          context.fillRect(x, y, cellWidth - gap, rowHeight - gap)
          context.fillStyle = colours.line
          context.fillRect(x, y + rowHeight - 1, cellWidth, 1)
        } else if (mid && lens === "bar") {
          context.fillStyle = colours.empty
          context.fillRect(x, y, cellWidth - gap, rowHeight - gap)
          const n = cell && typeof cell[1] === "number" ? cell[1] : 0
          context.fillStyle = colours.scale[3]
          context.fillRect(x, y + 1, Math.max((cellWidth - gap) * n, 0), rowHeight - gap - 2)
        } else {
          context.fillStyle = this.cellColour(cell, colours)
          context.fillRect(x, y, cellWidth - gap, rowHeight - gap)
        }
        if (mid && Array.isArray(cell && cell[4]) && cell[4].length > 1) {
          this.drawSparkline(context, cell[4], x + 3, y + 2, Math.min(cellWidth * 0.45, 60), rowHeight - 4, colours)
        }
        if (mid && cell && cell[0]) {
          context.fillStyle = lens === "band" && cell[2] >= 3 && cell[3] === "sequential" ? colours.surface : colours.ink
          context.textBaseline = "middle"
          const text = String(cell[0])
          const inset = Array.isArray(cell[4]) && cell[4].length > 1 ? Math.min(cellWidth * 0.45, 60) + 6 : 0
          const maxChars = Math.max(Math.floor((cellWidth - 6 - inset) / (rowHeight * 0.36)), 1)
          context.fillText(text.length > maxChars ? text.slice(0, maxChars - 1) + "…" : text, x + 3 + inset, y + rowHeight / 2)
        }
      })
    }
    if (headerHeight > 0) this.drawHeader(context, cellWidth, headerHeight, width, colours)
    if (this.rect) {
      context.strokeStyle = colours.ink
      context.setLineDash([4, 2])
      context.strokeRect(this.rect.x0, this.rect.y0 - top + headerHeight, this.rect.x1 - this.rect.x0, this.rect.y1 - this.rect.y0)
      context.setLineDash([])
    }
  },

  // A trend cell's twelve values as a small line, left of its text.
  drawSparkline(context, series, x, y, width, height, colours) {
    const lo = Math.min(...series)
    const hi = Math.max(...series)
    const span = hi === lo ? 1 : hi - lo
    const step = width / (series.length - 1)
    context.strokeStyle = colours.scale[3]
    context.lineWidth = 1
    context.beginPath()
    series.forEach((value, index) => {
      const px = x + index * step
      const py = y + height - ((value - lo) / span) * height
      if (index === 0) context.moveTo(px, py)
      else context.lineTo(px, py)
    })
    context.stroke()
  },

  drawHeader(context, cellWidth, headerHeight, width, colours) {
    context.fillStyle = colours.empty
    context.fillRect(0, 0, width, headerHeight)
    context.fillStyle = colours.line
    context.fillRect(0, headerHeight - 1, width, 1)
    context.fillStyle = colours.ink
    context.font = `600 ${Math.max(Math.floor(this.zoom * 0.62), 8)}px ${getComputedStyle(this.el).fontFamily}`
    context.textBaseline = "middle"
    const maxChars = Math.max(Math.floor((cellWidth - 6) / (this.zoom * 0.36)), 1)
    this.columns.forEach((column, c) => {
      const text = column.short || column.label
      context.fillText(text.length > maxChars ? text.slice(0, maxChars - 1) + "…" : text, c * cellWidth + 3, headerHeight / 2)
    })
  },

  // --- hover -----------------------------------------------------------

  cellAt(event) {
    const box = this.canvas.getBoundingClientRect()
    const viewport = this.viewport()
    const x = event.clientX - box.left
    const y = event.clientY - box.top + viewport.scrollTop - this.headerHeight()
    const row = Math.floor(y / this.zoom)
    const col = Math.floor(x / this.cellWidth())
    if (row < 0 || row >= this.total || col < 0 || col >= this.columns.length) return null
    return {row, col, x, y}
  },

  hover(event) {
    if (this.rect) {
      const at = this.cellAt(event)
      if (at) {
        this.rect.x1 = at.x
        this.rect.y1 = at.y
        this.draw()
      }
      return
    }
    const at = this.cellAt(event)
    if (!at) return this.hideTooltip()
    clearTimeout(this.hoverTimer)
    this.hoverTimer = setTimeout(() => this.showTooltip(at, event), HOVER_DEBOUNCE_MS)
  },

  showTooltip(at, event) {
    const row = this.rows.get(at.row)
    const column = this.columns[at.col]
    const tooltip = this.el.querySelector("[role=status]")
    if (!tooltip || !column) return
    const place = (text) => {
      tooltip.textContent = `${column.label}: ${text === "" || text == null ? "—" : text}`
      tooltip.classList.remove("hidden")
      const box = this.viewport().getBoundingClientRect()
      tooltip.style.left = `${event.clientX - box.left + this.viewport().scrollLeft + 12}px`
      tooltip.style.top = `${event.clientY - box.top + this.viewport().scrollTop + 12}px`
    }
    const cell = row ? row[1][at.col] : null
    if (cell && cell[0] !== null && cell[0] !== undefined) {
      place(cell[0])
    } else {
      // The carpet window carries no text; ask the host for this one value.
      this.push({op: "cell", id: this.el.id, row: at.row, col: column.id}, (reply) => place(reply && reply.text))
    }
  },

  hideTooltip() {
    clearTimeout(this.hoverTimer)
    const tooltip = this.el.querySelector("[role=status]")
    if (tooltip) tooltip.classList.add("hidden")
  },

  // --- rectangle zoom ----------------------------------------------------

  rectStart(event) {
    if (event.button !== 0) return
    const at = this.cellAt(event)
    if (!at) return
    this.rect = {x0: at.x, y0: at.y, x1: at.x, y1: at.y}
    this.hideTooltip()
  },

  rectEnd(event) {
    if (!this.rect) return
    const rect = this.rect
    this.rect = null
    const at = this.cellAt(event)
    if (at) {
      rect.x1 = at.x
      rect.y1 = at.y
    }
    const rows = Math.abs(rect.y1 - rect.y0) / this.zoom
    const cols = Math.abs(rect.x1 - rect.x0) / this.cellWidth()
    if (rows < 1 && cols < 1) {
      this.draw()
      return
    }
    // A small set leaves the viewport only as tall as its rows; the fit is
    // computed for the room the page has, so a rectangle still zooms in.
    const viewport = this.viewport()
    this.push({
      op: "zoom_rect",
      from_row: Math.floor(Math.min(rect.y0, rect.y1) / this.zoom),
      to_row: Math.ceil(Math.max(rect.y0, rect.y1) / this.zoom),
      from_col: Math.floor(Math.min(rect.x0, rect.x1) / this.cellWidth()),
      to_col: Math.ceil(Math.max(rect.x0, rect.x1) / this.cellWidth()),
      width: Math.max(viewport.clientWidth, 320),
      height: Math.max(viewport.clientHeight, Math.floor(window.innerHeight * 0.6)),
    })
  },
}

export default FlexTable
