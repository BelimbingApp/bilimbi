// shell_controls.js: the top bar's time display and theme controls and the
// account disclosure, driven by the AppShell hook. See the comment at the top
// of the module.
import {test, beforeEach, afterEach, mock} from "node:test"
import assert from "node:assert/strict"
import ShellControls from "../js/shell_controls.js"
import {focused, render} from "./support/hook.mjs"

// The controls as `ShellComponents.display_controls/1` and `account_menu/1`
// render them inside the shell, trimmed to what the module touches.
const SHELL = `
  <div id="app-shell" data-theme-choice="light">
    <div id="app-display">
      <div data-timezone-menu>
        <button type="button" id="app-display-timezone" data-timezone-toggle
                aria-expanded="false" aria-controls="app-display-timezone-panel">Company</button>
        <div id="app-display-timezone-panel" data-timezone-panel hidden>
          <button type="button" id="app-display-company" data-preference-kind="timezone" data-preference-value="company">Company</button>
          <button type="button" id="app-display-utc" data-preference-kind="timezone" data-preference-value="utc">UTC</button>
        </div>
      </div>
      <div role="group" aria-label="Theme">
        <button type="button" id="app-display-light" data-preference-kind="theme" data-preference-value="light">Light</button>
        <button type="button" id="app-display-dark" data-preference-kind="theme" data-preference-value="dark">Dark</button>
        <button type="button" id="app-display-system" data-preference-kind="theme" data-preference-value="system">System</button>
      </div>
    </div>
    <div id="app-preference-feedback" hidden role="status"></div>
    <div id="app-user">
      <button id="app-user-toggle" type="button" data-account-toggle
              aria-expanded="false" aria-controls="app-user-panel">Account</button>
      <section id="app-user-panel" data-account-panel hidden>
        <a id="app-user-settings" href="/settings">Settings</a>
      </section>
    </div>
    <main id="app-content"><button id="elsewhere" type="button">Elsewhere</button></main>
  </div>`

let controls
let replies

beforeEach(() => {
  delete document.documentElement.dataset.theme
  replies = []
  const el = render(SHELL, "app-shell")
  controls = new ShellControls({
    el,
    pushEvent: (event, payload, reply) => replies.push({event, payload, reply}),
  })
})

afterEach(() => {
  controls.destroy()
  mock.timers.reset()
})

const $ = (id) => document.getElementById(id)
const click = (id) => $(id).click()
const feedback = () => ($("app-preference-feedback").hidden ? null : $("app-preference-feedback").textContent)
const themeButtons = () => ["light", "dark", "system"].map((v) => $(`app-display-${v}`))
const escape = () =>
  document.activeElement.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true, cancelable: true}))

// A server patch re-renders the static markup: panels hidden, triggers
// collapsed, the live region blank, the theme choice as saved.
function serverPatch(themeChoice = $("app-shell").dataset.themeChoice) {
  for (const panel of document.querySelectorAll("[data-account-panel], [data-timezone-panel]")) panel.hidden = true
  for (const trigger of document.querySelectorAll("[aria-controls]")) trigger.setAttribute("aria-expanded", "false")
  $("app-preference-feedback").hidden = true
  $("app-preference-feedback").textContent = ""
  $("app-shell").dataset.themeChoice = themeChoice
  controls.apply()
}

test("the saved theme is projected onto the document, and system leaves it to the device", () => {
  assert.equal(document.documentElement.dataset.theme, "light")

  serverPatch("system")
  assert.equal(document.documentElement.dataset.theme, undefined)
})

test("a save sends one request, disables every choice until it lands, and a second press is dropped", () => {
  click("app-display-dark")
  click("app-display-system")

  assert.deepEqual(replies.map(({event, payload}) => ({event, payload})), [
    {event: "shell:preference", payload: {kind: "theme", value: "dark"}},
  ])
  assert.ok(themeButtons().every((button) => button.disabled))
  assert.equal(feedback(), "Saving display preference…")
})

test("a refused save says so, keeps the previous choice, and hands back the control", () => {
  $("app-display-dark").focus()
  click("app-display-dark")
  $("elsewhere").focus()
  replies[0].reply({ok: false})

  assert.equal(document.documentElement.dataset.theme, "light")
  assert.match(feedback(), /Could not save display preference/)
  assert.equal($("app-preference-feedback").classList.contains("text-danger"), true)
  assert.ok(themeButtons().every((button) => !button.disabled))
  assert.equal(focused(), "app-display-dark")

  click("app-display-dark")
  assert.equal(replies.length, 2)
})

test("a saved theme is confirmed and applied once the server patches the choice", () => {
  click("app-display-dark")
  serverPatch("dark")
  replies[0].reply({ok: true})

  assert.equal(document.documentElement.dataset.theme, "dark")
  assert.equal(feedback(), "Theme saved.")
  assert.equal($("app-preference-feedback").classList.contains("text-danger"), false)
})

test("an open panel and its confirmation survive a server patch, and focus returns to the trigger", () => {
  click("app-display-timezone")
  assert.equal($("app-display-timezone-panel").hidden, false)
  assert.equal($("app-display-timezone").getAttribute("aria-expanded"), "true")
  assert.equal(focused(), "app-display-company")

  serverPatch()
  assert.equal($("app-display-timezone-panel").hidden, false)
  assert.equal($("app-display-timezone").getAttribute("aria-expanded"), "true")

  click("app-display-utc")
  assert.equal($("app-display-utc").disabled, true)
  replies[0].reply({ok: true})

  assert.equal($("app-display-timezone-panel").hidden, true)
  assert.equal($("app-display-timezone").getAttribute("aria-expanded"), "false")
  assert.equal(feedback(), "Time display saved.")
  assert.equal($("app-display-utc").disabled, false)
  assert.equal(focused(), "app-display-timezone")

  serverPatch()
  assert.equal(feedback(), "Time display saved.")
})

test("a theme save outside the open account panel keeps focus on the operated control", () => {
  click("app-user-toggle")
  assert.equal(focused(), "app-user-settings")

  $("app-display-dark").focus()
  click("app-display-dark")
  replies[0].reply({ok: true})

  assert.equal($("app-user-panel").hidden, true)
  assert.equal(focused(), "app-display-dark")
})

test("one panel opens at a time, and a click outside closes it", () => {
  click("app-user-toggle")
  click("app-display-timezone")
  assert.equal($("app-user-panel").hidden, true)
  assert.equal($("app-display-timezone-panel").hidden, false)

  click("elsewhere")
  assert.equal($("app-display-timezone-panel").hidden, true)
})

test("Escape closes the open panel and returns focus to its trigger", () => {
  click("app-user-toggle")
  escape()

  assert.equal($("app-user-panel").hidden, true)
  assert.equal($("app-user-toggle").getAttribute("aria-expanded"), "false")
  assert.equal(focused(), "app-user-toggle")
})

test("tabbing out of an open panel closes it", async () => {
  click("app-user-toggle")
  $("elsewhere").focus()
  $("app-user-settings").dispatchEvent(new KeyboardEvent("keydown", {key: "Tab", bubbles: true}))
  await new Promise((resolve) => setTimeout(resolve, 0))

  assert.equal($("app-user-panel").hidden, true)
})

test("a save that is never answered says it could not be confirmed", () => {
  mock.timers.enable({apis: ["setTimeout"]})
  click("app-display-dark")

  mock.timers.tick(12000)

  assert.match(feedback(), /Save could not be confirmed/)
})

test("offline, nothing is sent; a save cut off by a disconnect is unresolved until reconnect", () => {
  controls.connection(false)
  assert.ok(themeButtons().every((button) => button.disabled))
  controls.save("theme", "dark", $("app-display-dark"))
  assert.equal(replies.length, 0)

  controls.connection(true)
  click("app-display-dark")
  controls.connection(false)
  assert.match(feedback(), /Connection lost/)

  // Rejoining re-renders the true saved state, so the notice must not survive.
  controls.connection(true)
  assert.equal(feedback(), null)
  serverPatch()
  assert.equal(feedback(), null)
  assert.ok(themeButtons().every((button) => !button.disabled))
})

test("a settled outcome survives a later disconnect and reconnect", () => {
  click("app-display-dark")
  replies[0].reply({ok: true})

  controls.connection(false)
  controls.connection(true)
  serverPatch()

  assert.equal(feedback(), "Theme saved.")
})
