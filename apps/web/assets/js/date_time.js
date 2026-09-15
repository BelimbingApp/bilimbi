// Keeps every rendered instant on the saved display mode.
//
// A mode change has to reach timestamps that are already on screen, including
// rows a LiveView stream handed to the DOM and never re-renders. So the shell
// publishes the live mode on #app-shell and this hook re-applies it in place.
//
// The server decides `company` and `utc` and writes both strings onto the
// element, so those two modes are a copy, never a re-format: the browser
// cannot disagree with the server about a string it did not produce. `local`
// is the one mode the server cannot decide — it does not know the browser's
// zone — so it is formatted here, in the reader's own locale and hour cycle.
const SHELL = "#app-shell"

// Every mounted instant, so one shell change repaints all of them without
// each element observing the shell separately.
const instances = new Set()

// One observer for the whole page, armed on the first mount. It re-arms if the
// shell element is ever replaced rather than patched, so a stale observer
// cannot leave every timestamp silently frozen on the previous mode.
let observer = null
let observed = null

const shell = () => document.querySelector(SHELL)

const liveMode = () => shell()?.dataset.displayMode || null

const observeShell = () => {
  const el = shell()
  if (!el || observed === el) return
  observer?.disconnect()
  observer = new MutationObserver(() => {
    for (const hook of instances) hook.renderDateTime()
  })
  observer.observe(el, {attributes: true, attributeFilter: ["data-display-mode"]})
  observed = el
}

// `local` renders the instant the way the reader's own device would: their
// locale orders the fields and chooses the hour cycle. The zone is named on
// `datetime` only, where the label qualifies a full date and time.
export const formatLocal = (value, timeZone, format) => {
  const options = {timeZone}

  if (format !== "time") {
    Object.assign(options, {day: "2-digit", month: "2-digit", year: "numeric"})
  }

  if (format !== "date") {
    Object.assign(options, {hour: "2-digit", minute: "2-digit"})
  }

  if (format === "datetime") options.timeZoneName = "short"

  return new Intl.DateTimeFormat(undefined, options).format(value)
}

const DateTime = {
  mounted() {
    instances.add(this)
    observeShell()
    this.renderDateTime()
  },

  updated() {
    this.renderDateTime()
  },

  destroyed() {
    instances.delete(this)
  },

  renderDateTime() {
    const value = new Date(this.el.dateTime)

    if (Number.isNaN(value.getTime())) return

    const mode = liveMode() || this.el.dataset.mode || "local"

    if (mode === "company" || mode === "utc") {
      // The server already rendered both. Copy, never re-format.
      const text = mode === "company" ? this.el.dataset.textCompany : this.el.dataset.textUtc
      this.showServerText(text)
      return
    }

    const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"
    let text

    try {
      text = formatLocal(value, timeZone, this.el.dataset.format)
    } catch {
      // A browser that cannot format this zone falls back to the server's
      // stored-UTC text. Keeping whatever is there would leave the previous
      // mode's string under a control that now reports a different mode.
      this.showServerText(this.el.dataset.textUtc)
      return
    }

    this.el.textContent = text
    this.el.dataset.timezone = timeZone
    this.el.title = `Rendered in ${timeZone}`
  },

  showServerText(text) {
    if (text) this.el.textContent = text
    delete this.el.dataset.timezone
    this.el.removeAttribute("title")
  },
}

export default DateTime
