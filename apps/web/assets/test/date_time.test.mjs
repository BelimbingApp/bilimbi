// date_time.js: every `<.datetime>` on screen follows the saved display mode.
// The server writes the company and UTC strings; only the reader's local
// time is formatted here. How that local text reads in a given locale is
// pinned under two host locales by `date_time_js_test.exs`.
import {test, beforeEach, afterEach} from "node:test"
import assert from "node:assert/strict"
import DateTime, {formatLocal} from "../js/date_time.js"
import {mountHook, render, settle} from "./support/hook.mjs"

const INSTANT = "2026-07-24T07:00:00Z"
const UTC_TEXT = "24/07/2026, 07:00 UTC"
const COMPANY_TEXT = "24/07/2026, 15:00 +08"

let mounted = []
const browserZone = process.env.TZ

beforeEach(() => {
  process.env.TZ = "Asia/Kuala_Lumpur"
  render(`<div id="app-shell" data-display-mode="company"><main id="rows"></main></div>`, "rows")
})

afterEach(() => {
  for (const {hook} of mounted) hook.destroyed()
  mounted = []
  if (browserZone === undefined) delete process.env.TZ
  else process.env.TZ = browserZone
})

// One instant as `datetime/1` renders it. `followShell` is true unless the
// caller pinned a display context of its own.
function instant(id, {mode = "company", followShell = true, dateTime = INSTANT} = {}) {
  document.getElementById("rows").insertAdjacentHTML(
    "beforeend",
    `<time id="${id}" datetime="${dateTime}" data-format="datetime" data-precision="minute"
           data-mode="${mode}" data-text-company="${COMPANY_TEXT}" data-text-utc="${UTC_TEXT}"
           ${followShell ? 'data-follow-shell="true"' : ""}>${COMPANY_TEXT}</time>`
  )
  const el = document.getElementById(id)
  mounted.push(mountHook(DateTime, el))
  return el
}

const shell = () => document.getElementById("app-shell")

async function switchShell(mode) {
  shell().dataset.displayMode = mode
  await settle()
}

test("company and UTC modes show the server's own string", async () => {
  const el = instant("started-at")
  assert.equal(el.textContent, COMPANY_TEXT)

  await switchShell("utc")
  assert.equal(el.textContent, UTC_TEXT)
  assert.equal(el.hasAttribute("title"), false)
  assert.equal(el.dataset.timezone, undefined)
})

test("local mode renders the instant in the browser's zone and says which", async () => {
  const el = instant("started-at")

  await switchShell("local")

  assert.equal(el.textContent, formatLocal(new Date(INSTANT), "Asia/Kuala_Lumpur", "datetime", "minute"))
  assert.notEqual(el.textContent, formatLocal(new Date(INSTANT), "UTC", "datetime", "minute"))
  assert.equal(el.dataset.timezone, "Asia/Kuala_Lumpur")
  assert.equal(el.title, "Rendered in Asia/Kuala_Lumpur")
})

test("the zone is the browser's, whichever it is", () => {
  process.env.TZ = "America/New_York"
  const el = instant("started-at", {mode: "local", followShell: false})

  assert.equal(el.dataset.timezone, "America/New_York")
  assert.equal(el.textContent, formatLocal(new Date(INSTANT), "America/New_York", "datetime", "minute"))
})

test("leaving local mode drops the zone note", async () => {
  const el = instant("started-at")
  await switchShell("local")

  await switchShell("company")

  assert.equal(el.textContent, COMPANY_TEXT)
  assert.equal(el.hasAttribute("title"), false)
  assert.equal(el.dataset.timezone, undefined)
})

test("one mode change repaints every instant on the page, re-rendered or not", async () => {
  const first = instant("row-1-started")
  const second = instant("row-2-started")

  await switchShell("utc")

  assert.equal(first.textContent, UTC_TEXT)
  assert.equal(second.textContent, UTC_TEXT)
})

test("an instant pinned to a display context ignores the shell", async () => {
  const pinned = instant("audit-at", {mode: "utc", followShell: false})
  assert.equal(pinned.textContent, UTC_TEXT)

  await switchShell("company")
  await switchShell("local")

  assert.equal(pinned.textContent, UTC_TEXT)
})

test("a patch re-applies the current mode over the server's default text", async () => {
  const el = instant("started-at")
  await switchShell("utc")

  // The server re-renders the element with the company string it defaults to.
  el.textContent = COMPANY_TEXT
  mounted.at(-1).hook.updated()

  assert.equal(el.textContent, UTC_TEXT)
})

test("a browser that cannot format its own zone falls back to the UTC string", async (t) => {
  // A zone name this browser's Intl data does not know.
  const resolvedOptions = Intl.DateTimeFormat.prototype.resolvedOptions
  t.mock.method(Intl.DateTimeFormat.prototype, "resolvedOptions", function () {
    return {...resolvedOptions.call(this), timeZone: "Mars/Olympus_Mons"}
  })

  const el = instant("started-at")
  await switchShell("local")

  assert.equal(el.textContent, UTC_TEXT)
  assert.equal(el.hasAttribute("title"), false)
  assert.equal(el.dataset.timezone, undefined)
})

test("an unreadable instant keeps the server's text", async () => {
  const el = instant("started-at", {dateTime: "not a time"})

  await switchShell("utc")

  assert.equal(el.textContent, COMPANY_TEXT)
})
