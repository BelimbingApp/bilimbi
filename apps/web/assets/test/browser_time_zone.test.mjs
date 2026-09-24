// browser_time_zone.js: tells the view which zone this browser shows local
// times in, so date filters bound the days the reader actually sees.
import {test, afterEach} from "node:test"
import assert from "node:assert/strict"
import BrowserTimeZone from "../js/browser_time_zone.js"
import {mountHook, render} from "./support/hook.mjs"

const browserZone = process.env.TZ

afterEach(() => {
  if (browserZone === undefined) delete process.env.TZ
  else process.env.TZ = browserZone
})

const mountPanel = () =>
  mountHook(BrowserTimeZone, render(`<section id="schedule-history-panel"></section>`, "schedule-history-panel"))

test("reports the browser's zone once, on mount", () => {
  process.env.TZ = "Asia/Kuala_Lumpur"

  const {pushes} = mountPanel()

  assert.deepEqual(pushes.map(({event, payload}) => ({event, payload})), [
    {event: "browser_timezone", payload: {timezone: "Asia/Kuala_Lumpur"}},
  ])
})

test("reports the same zone the local clock renders in", () => {
  process.env.TZ = "America/New_York"

  const {pushes} = mountPanel()

  assert.equal(pushes[0].payload.timezone, "America/New_York")
})

test("a browser that reports no zone is treated as UTC", (t) => {
  const resolvedOptions = Intl.DateTimeFormat.prototype.resolvedOptions
  t.mock.method(Intl.DateTimeFormat.prototype, "resolvedOptions", function () {
    return {...resolvedOptions.call(this), timeZone: undefined}
  })

  const {pushes} = mountPanel()

  assert.deepEqual(pushes[0].payload, {timezone: "UTC"})
})
