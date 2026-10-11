// Reports the browser's own time zone to the view that mounted this.
//
// Under the local display mode every instant is formatted in the browser
// (see `date_time.js`), so only the browser knows which calendar day a row
// is shown on. A screen whose date filters bound displayed days mounts this
// on the region that holds them and receives one `browser_timezone` event;
// the server proves the name against its own time zone database and keeps
// bounding UTC, the text it rendered itself, when it cannot honor it. The
// hook reports again when the top-bar clock mode (`data-display-mode` on
// `#app-shell`) changes, so the screen recomputes its days without a reload.
//
// The zone is the same expression `date_time.js` formats with, so the day a
// row displays on and the day the server bounds are read from one source.
const BrowserTimeZone = {
  mounted() {
    const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"
    this.reportTimeZone = () => this.pushEvent("browser_timezone", {timezone: timeZone})
    this.reportTimeZone()
    this.observeClock()
  },
  updated() {
    this.observeClock()
  },
  observeClock() {
    const shell = document.querySelector("#app-shell")
    if (this.clockShell === shell) return
    this.clockObserver?.disconnect()
    this.clockShell = shell
    if (!shell) return
    // A saved top-bar mode changes displayed calendar days as well as labels.
    // Re-report the browser zone so the host recomputes its range from the
    // freshly authorized shell preferences, without a reload or a URL change.
    this.clockObserver = new MutationObserver(() => this.reportTimeZone())
    this.clockObserver.observe(shell, {attributes: true, attributeFilter: ["data-display-mode"]})
  },
  destroyed() {
    this.clockObserver?.disconnect()
  },
}

export default BrowserTimeZone
