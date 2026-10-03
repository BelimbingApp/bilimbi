// Keeps a `<.tabs>` strip on one line. Tabs that do not fit scroll inside the
// strip instead of widening the page. The edge buttons are a pointer
// affordance: they stay out of tab order, and focusing a tab scrolls it
// clear of the edge that would cover it. The buttons and the fade exist
// only while a tab actually sits outside the strip.
const EDGE = 32

const TabStrip = {
  mounted() {
    this.scroller = this.el.querySelector("[data-tab-scroller]")
    this.start = this.el.querySelector("[data-tab-scroll='start']")
    this.end = this.el.querySelector("[data-tab-scroll='end']")

    this.onScroll = () => this.sync()
    this.onFocus = (event) => {
      const tab = event.target.closest("[data-tab]")
      if (!tab || !this.scroller.contains(tab)) return
      reveal(this.scroller, tab)
      this.sync()
    }
    // A click would focus the button and drop the tabs out of the next Tab
    // press. Preventing the mousedown focus keeps keyboard order on the tabs.
    this.onMouseDown = (event) => {
      const button = event.target.closest("[data-tab-scroll]")
      if (button && this.el.contains(button)) event.preventDefault()
    }
    this.onClick = (event) => {
      const button = event.target.closest("[data-tab-scroll]")
      if (!button || !this.el.contains(button)) return
      const toward = button.dataset.tabScroll === "start" ? "start" : "end"
      revealNeighbor(this.scroller, toward)
      this.sync()
    }

    this.scroller.addEventListener("scroll", this.onScroll, {passive: true})
    this.el.addEventListener("focusin", this.onFocus)
    this.el.addEventListener("mousedown", this.onMouseDown)
    this.el.addEventListener("click", this.onClick)

    this.resize = new ResizeObserver(() => this.sync())
    this.resize.observe(this.scroller)

    const current = this.scroller.querySelector("[aria-current='page']")
    if (current) reveal(this.scroller, current)
    this.sync()
  },

  updated() {
    const current = this.scroller.querySelector("[aria-current='page']")
    if (current) reveal(this.scroller, current)
    this.sync()
  },

  destroyed() {
    this.resize.disconnect()
    this.scroller.removeEventListener("scroll", this.onScroll)
    this.el.removeEventListener("focusin", this.onFocus)
    this.el.removeEventListener("mousedown", this.onMouseDown)
    this.el.removeEventListener("click", this.onClick)
  },

  sync() {
    paint(this.scroller, this.start, this.end)
  },
}

function laidOut(scroller) {
  return scroller.clientWidth > 0 && scroller.scrollWidth > 0
}

function span(tab) {
  return {start: tab.offsetLeft, end: tab.offsetLeft + tab.offsetWidth}
}

function view(scroller) {
  return {
    start: scroller.scrollLeft + EDGE,
    end: scroller.scrollLeft + scroller.clientWidth - EDGE,
    max: Math.max(0, scroller.scrollWidth - scroller.clientWidth),
  }
}

function reveal(scroller, tab) {
  if (!laidOut(scroller)) return

  const box = span(tab)
  const visible = view(scroller)

  if (box.start < visible.start) {
    scroller.scrollLeft = Math.max(0, box.start - EDGE)
  } else if (box.end > visible.end) {
    scroller.scrollLeft = Math.min(visible.max, box.end - scroller.clientWidth + EDGE)
  }
}

function revealNeighbor(scroller, toward) {
  if (!laidOut(scroller)) return

  const visible = view(scroller)
  const tabs = [...scroller.querySelectorAll("[data-tab]")]
  const target =
    toward === "end"
      ? tabs.find((tab) => span(tab).end > visible.end + 1)
      : [...tabs].reverse().find((tab) => span(tab).start < visible.start - 1)

  if (target) reveal(scroller, target)
}

function paint(scroller, start, end) {
  if (!laidOut(scroller)) {
    start.hidden = true
    end.hidden = true
    mask(scroller, "")
    return
  }

  const max = scroller.scrollWidth - scroller.clientWidth
  const overflow = max > 1
  const showStart = overflow && scroller.scrollLeft > 1
  const showEnd = overflow && scroller.scrollLeft < max - 1
  start.hidden = !showStart
  end.hidden = !showEnd
  mask(
    scroller,
    showStart && showEnd ? fadeBoth : showStart ? fadeStart : showEnd ? fadeEnd : "",
  )
}

const fadeEnd = "linear-gradient(to left, transparent, #000 2rem)"
const fadeStart = "linear-gradient(to right, transparent, #000 2rem)"
const fadeBoth =
  "linear-gradient(to right, transparent, #000 2rem, #000 calc(100% - 2rem), transparent)"

function mask(scroller, value) {
  scroller.style.maskImage = value
  scroller.style.webkitMaskImage = value
}

export default TabStrip
