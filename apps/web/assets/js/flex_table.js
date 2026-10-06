// FlexTable: the browser half of `Bilimbi.Base.UI.Components.FlexTable.flex_table/1`.
//
// The server renders the whole table; this hook owns the three things only
// a browser can do: dragging a chip or a heading onto another to reorder
// the columns, walking the add-a-column box's suggestions with the arrow keys, and
// the bar widths the CSP refuses to take from a style attribute. A reorder
// is pushed to the host as the one `data-event` with `op: "move"`; nothing
// here is the source of truth.

const FlexTable = {
  mounted() {
    this.drag = null
    this.readDataset()

    this.onDragStart = (event) => this.dragStart(event)
    this.onDragOver = (event) => this.dragOver(event)
    this.onDragLeave = (event) => this.dragLeave(event)
    this.onDrop = (event) => this.drop(event)
    this.onDragEnd = () => this.dragEnd()
    this.onKeyDown = (event) => this.addBarKeys(event)

    this.el.addEventListener("dragstart", this.onDragStart)
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("dragleave", this.onDragLeave)
    this.el.addEventListener("drop", this.onDrop)
    this.el.addEventListener("dragend", this.onDragEnd)
    this.el.addEventListener("keydown", this.onKeyDown)

    this.applyBars()
  },

  updated() {
    this.readDataset()
    this.applyBars()
  },

  destroyed() {
    this.el.removeEventListener("dragstart", this.onDragStart)
    this.el.removeEventListener("dragover", this.onDragOver)
    this.el.removeEventListener("dragleave", this.onDragLeave)
    this.el.removeEventListener("drop", this.onDrop)
    this.el.removeEventListener("dragend", this.onDragEnd)
    this.el.removeEventListener("keydown", this.onKeyDown)
  },

  readDataset() {
    this.event = this.el.dataset.event
    this.target = this.el.dataset.target || null
  },

  push(payload) {
    if (this.target) this.pushEventTo(this.target, this.event, payload)
    else this.pushEvent(this.event, payload)
  },

  // --- bars (CSSOM, because the CSP refuses inline style) ---------------

  applyBars() {
    for (const bar of this.el.querySelectorAll("[data-bar]")) {
      const percent = parseFloat(bar.dataset.bar)
      bar.style.width = Number.isFinite(percent) ? `${percent}%` : "0%"
    }
  },

  // --- drag to reorder ---------------------------------------------------

  dragStart(event) {
    const source = event.target.closest("[data-chip], [data-header]")
    if (!source) return
    this.drag = {spec: source.dataset.chip || source.dataset.header, kind: source.dataset.chip ? "chip" : "header"}
    source.dataset.dragging = "true"
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.drag.spec)
  },

  dragOver(event) {
    if (!this.drag) return
    const over = event.target.closest("[data-chip], [data-header]")
    if (!over) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.clearDropMarks()
    const spec = over.dataset.chip || over.dataset.header
    if (spec !== this.drag.spec) over.dataset.drop = this.before(event, over) ? "before" : "after"
  },

  dragLeave(event) {
    const left = event.target.closest && event.target.closest("[data-chip], [data-header]")
    if (left) delete left.dataset.drop
  },

  drop(event) {
    if (!this.drag) return
    event.preventDefault()
    const over = event.target.closest("[data-chip], [data-header]")
    const spec = this.drag.spec
    if (over) {
      const target = over.dataset.chip || over.dataset.header
      if (target !== spec) {
        const before = this.before(event, over)
        this.push({op: "move", spec, before: before ? target : this.after(target)})
      }
    }
    this.dragEnd()
  },

  // The spec following `target` in the current order, or null at the end.
  // The chips are the order: the server renders one per column.
  after(target) {
    const specs = [...this.el.querySelectorAll("[data-chip]")].map((chip) => chip.dataset.chip)
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
    this.drag = null
  },

  clearDropMarks() {
    for (const el of this.el.querySelectorAll("[data-drop]")) delete el.dataset.drop
  },

  // In the add-a-column box, the arrow keys walk the suggestions and Enter picks the
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
}

export default FlexTable
