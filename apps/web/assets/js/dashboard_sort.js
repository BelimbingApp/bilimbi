// Drag-to-reorder for the dashboard widget grid. Server-driven: the hook only
// computes the DOM order after a drop and pushes it as `reorder-widgets`; the
// LiveView validates the order is a permutation of its current widget ids
// before persisting anything, so a stale or forged push changes nothing.
//
// Reordering is always available on desktop; dropping a card saves immediately.
// HTML5 drag and drop still has no touch support, so the keyboard move buttons
// in customize mode remain the accessible reorder path.
const DashboardSort = {
  mounted() {
    this.dragged = null

    this.onDragStart = (e) => {
      const item = e.target.closest("[data-widget-id]")
      if (!item) return

      this.dragged = item
      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData("text/plain", item.dataset.widgetId)
      item.classList.add("opacity-40")
    }

    this.onDragOver = (e) => {
      if (!this.dragged) return

      e.preventDefault()
      e.dataTransfer.dropEffect = "move"

      const target = e.target.closest("[data-widget-id]")
      if (!target || target === this.dragged) return

      // Insert before or after the hovered item depending on the pointer's
      // half of it, so the widget follows the cursor the way users expect.
      const rect = target.getBoundingClientRect()
      const before = e.clientY < rect.top + rect.height / 2

      if (before) {
        target.parentNode.insertBefore(this.dragged, target)
      } else {
        target.parentNode.insertBefore(this.dragged, target.nextSibling)
      }
    }

    this.onDrop = (e) => {
      if (!this.dragged) return
      e.preventDefault()
    }

    this.onDragEnd = () => {
      if (!this.dragged) return

      this.dragged.classList.remove("opacity-40")
      this.dragged = null

      const ids = [...this.el.querySelectorAll("[data-widget-id]")].map(
        (el) => el.dataset.widgetId
      )
      this.pushEvent("reorder-widgets", {ids})
    }

    this.el.addEventListener("dragstart", this.onDragStart)
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("drop", this.onDrop)
    this.el.addEventListener("dragend", this.onDragEnd)
  },

  destroyed() {
    this.el.removeEventListener("dragstart", this.onDragStart)
    this.el.removeEventListener("dragover", this.onDragOver)
    this.el.removeEventListener("drop", this.onDrop)
    this.el.removeEventListener("dragend", this.onDragEnd)
  },
}

export default DashboardSort
