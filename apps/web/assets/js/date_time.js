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
// zone — so it is formatted here, pinned to the server's own convention:
//
//     :datetime   02/01/2026, 00:30 +08
//     :date       02/01/2026 +08
//     :time       00:30 +08
//
// Both halves of that convention were regressions once and are covered by
// apps/web/test/bilimbi_web/date_time_js_test.exs:
//
//   * The locale is an explicit literal. `Intl.DateTimeFormat(undefined, …)`
//     follows the browser, and a US-locale browser renders 24/07/2026 as
//     07/24/2026 — day and month transposed against the server.
//   * The zone label is emitted for all three formats, not only `datetime`.
//
// The label comes from `longOffset` rather than `short`, because ICU's short
// names are localized: the same zone reads "GMT+8" to an en-GB browser and
// "MYT" to an ms-MY one, so two users in one zone would disagree. `longOffset`
// under a pinned locale is stable, and the IANA-shaped label is derived from
// it here.
const LOCALE = "en-GB"
const SHELL = "#app-shell"

// Every mounted instant, so one shell change repaints all of them without
// each element observing the shell separately.
const instances = new Set()
let observer = null

const shell = () => document.querySelector(SHELL)

const liveDisplay = () => {
  const el = shell()
  return {
    mode: el?.dataset.displayMode || null,
    timeZone: el?.dataset.displayTimezone || null,
  }
}

// One observer for the whole page, armed on the first mount. It re-arms if the
// shell element is ever replaced rather than patched, so a stale observer
// cannot leave every timestamp silently frozen on the previous mode.
let observed = null

const observeShell = () => {
  const el = shell()
  if (!el || observed === el) return
  observer?.disconnect()
  observer = new MutationObserver(() => {
    for (const hook of instances) hook.renderDateTime()
  })
  observer.observe(el, {
    attributes: true,
    attributeFilter: ["data-display-mode", "data-display-timezone"],
  })
  observed = el
}

// IANA writes a numeric zone abbreviation as sign, two-digit hours, and
// minutes only when they are not zero: +08, +0545, -0330. ICU writes the same
// offset as GMT+08:00. Zero offset is labelled UTC, matching what the server
// writes for stored-UTC text, so a zero-offset browser reads the same label in
// local and utc modes — which show the same wall clock.
const offsetLabel = value => {
  const match = /^GMT([+-])(\d{2}):(\d{2})$/.exec(value)
  if (!match) return value === "GMT" ? "UTC" : value
  const [, sign, hours, minutes] = match
  if (hours === "00" && minutes === "00") return "UTC"
  return `${sign}${hours}${minutes === "00" ? "" : minutes}`
}

// The server's layout, assembled from parts rather than handed to a locale.
export const formatLocal = (value, timeZone, format) => {
  const parts = new Intl.DateTimeFormat(LOCALE, {
    timeZone,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
    timeZoneName: "longOffset",
  }).formatToParts(value)

  const part = type => parts.find(candidate => candidate.type === type)?.value
  const date = `${part("day")}/${part("month")}/${part("year")}`
  const time = `${part("hour")}:${part("minute")}`
  const label = offsetLabel(part("timeZoneName"))

  if (format === "date") return `${date} ${label}`
  if (format === "time") return `${time} ${label}`
  return `${date}, ${time} ${label}`
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

    // An instant given an explicit display context follows that context, not
    // the shell: the caller has already decided what it is showing.
    const live = this.el.dataset.followShell === "true" ? liveDisplay() : {}
    const mode = live.mode || this.el.dataset.mode || "local"

    if (mode === "company" || mode === "utc") {
      // The server already rendered both. Copy, never re-format.
      const text = mode === "company" ? this.el.dataset.textCompany : this.el.dataset.textUtc
      if (text) this.el.textContent = text
      delete this.el.dataset.timezone
      this.el.removeAttribute("title")
      return
    }

    const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"

    try {
      this.el.textContent = formatLocal(value, timeZone, this.el.dataset.format)
    } catch {
      // A browser that cannot render the zone keeps the truthful server text.
      return
    }

    this.el.dataset.timezone = timeZone
    this.el.title = `Rendered in ${timeZone}`
  },
}

export default DateTime
