// app_shell.js: the authenticated shell's sidebar -- the desktop rail and its
// width, the mobile drawer, navigation branches and pins. See the comment at
// the top of the hook.
import {test, beforeEach, afterEach} from "node:test"
import assert from "node:assert/strict"
import AppShell from "../js/app_shell.js"
import {focused, mountHook, render} from "./support/hook.mjs"

// happy-dom answers media queries from a fixed window size, so the
// breakpoint is stood in for here and can be crossed mid-test.
let viewport

function setViewport(desktop) {
  const listeners = new Set()
  const mq = {
    matches: desktop,
    addEventListener: (_type, listener) => listeners.add(listener),
    removeEventListener: (_type, listener) => listeners.delete(listener),
  }
  window.matchMedia = () => mq
  viewport = {
    cross(next) {
      mq.matches = next
      for (const listener of listeners) listener()
    },
  }
}

// The shell as `Layouts.app` renders it, trimmed to what the hook touches.
const SHELL = `
  <div id="app-shell" phx-hook="AppShell" data-theme-choice="light"
       data-sidebar-mode="desktop" data-sidebar-rail="false" data-sidebar-open="false">
    <header id="app-topbar">
      <button type="button" id="app-sidebar-toggle" aria-controls="app-sidebar" aria-expanded="false">Menu</button>
      <div id="app-topbar-main"><a id="app-brand" href="/dashboard">Bilimbi</a></div>
    </header>
    <div id="app-preference-feedback" hidden role="status"></div>
    <div id="app-workspace">
      <div id="app-sidebar-backdrop" aria-hidden="true"></div>
      <aside id="app-sidebar" tabindex="-1" role="navigation">
        <div id="app-pinned" hidden><div id="app-pinned-items"></div></div>
        <nav id="app-nav">
          <div class="group">
            <a href="/companies" id="nav-companies" data-nav-item="nav-companies" data-nav-label="Companies"
               data-phx-link="redirect" data-phx-link-state="push">Companies</a>
            <button type="button" id="nav-pin-companies" data-nav-pin="nav-companies"
                    aria-label="Pin Companies to sidebar" aria-pressed="false">Pin</button>
          </div>
          <section id="nav-branch-admin" data-nav-branch="admin"
                   data-nav-default-expanded="false" data-nav-expanded="false">
            <button type="button" id="nav-toggle-admin" data-nav-toggle
                    aria-controls="nav-children-admin" aria-expanded="false">Administration</button>
            <div id="nav-children-admin" class="app-nav-children" hidden>
              <a href="/users" id="nav-users">Users</a>
            </div>
          </section>
        </nav>
        <div id="app-user">
          <button id="app-user-toggle" type="button" data-account-toggle
                  aria-expanded="false" aria-controls="app-user-panel">Account</button>
          <section id="app-user-panel" data-account-panel hidden>
            <a id="app-user-settings" href="/settings">Settings</a>
          </section>
        </div>
      </aside>
      <div id="app-sidebar-drag" role="separator"></div>
      <main id="app-content">
        <button type="button" id="company-pin" data-nav-pin="record" data-nav-pin-record="true"
                data-nav-pin-label="Administration / Companies / Acme"
                data-nav-pin-url="/companies/1"
                aria-label="Pin this company to sidebar" aria-pressed="false">Pin</button>
      </main>
    </div>
    <footer id="app-statusbar"></footer>
  </div>`

let shell

function mount() {
  shell = mountHook(AppShell, render(SHELL, "app-shell"))
  return shell
}

beforeEach(() => {
  localStorage.clear()
  setViewport(true)
})

afterEach(() => shell?.hook.destroyed())

const $ = (id) => document.getElementById(id)
const click = (id) => $(id).click()
const key = (name, init = {}) =>
  (document.activeElement ?? document.body).dispatchEvent(new KeyboardEvent("keydown", {key: name, bubbles: true, cancelable: true, ...init}))
const inert = (id) => $(id).hasAttribute("inert")
const pinnedLinks = () =>
  [...$("app-pinned-items").querySelectorAll("a")].map((a) => a.pathname + a.search)
const storedPins = () => JSON.parse(localStorage.getItem("sidebarPinnedItems") ?? "[]")

test("on a phone the closed drawer is inert and hidden from assistive technology", () => {
  setViewport(false)
  mount()

  assert.equal(inert("app-sidebar"), true)
  assert.equal($("app-sidebar").getAttribute("aria-hidden"), "true")
  assert.equal($("app-sidebar-toggle").getAttribute("aria-expanded"), "false")
  assert.equal(inert("app-content"), false)
})

test("the open drawer is a modal dialog that inerts the rest of the shell but not its toggle", () => {
  setViewport(false)
  mount()

  click("app-sidebar-toggle")

  const sidebar = $("app-sidebar")
  assert.equal(inert("app-sidebar"), false)
  assert.equal(sidebar.getAttribute("role"), "dialog")
  assert.equal(sidebar.getAttribute("aria-modal"), "true")
  for (const region of ["app-content", "app-statusbar", "app-topbar-main"]) {
    assert.equal(inert(region), true, `${region} is not inert`)
    assert.equal($(region).getAttribute("aria-hidden"), "true")
  }
  assert.equal(inert("app-topbar"), false)
  assert.equal($("app-sidebar-toggle").getAttribute("aria-expanded"), "true")
  assert.equal(focused(), "nav-companies")
})

test("Escape closes the drawer and returns focus to where it was", () => {
  setViewport(false)
  mount()

  $("app-sidebar-toggle").focus()
  click("app-sidebar-toggle")
  key("Escape")

  assert.equal(inert("app-sidebar"), true)
  assert.equal($("app-sidebar").getAttribute("role"), "navigation")
  assert.equal(inert("app-content"), false)
  assert.equal(focused(), "app-sidebar-toggle")
})

test("Escape inside the drawer closes an open account panel first, and only that", () => {
  setViewport(false)
  mount()

  click("app-sidebar-toggle")
  click("app-user-toggle")
  assert.equal($("app-user-panel").hidden, false)

  key("Escape")

  assert.equal($("app-user-panel").hidden, true)
  assert.equal($("app-sidebar").getAttribute("aria-modal"), "true")
  assert.equal(focused(), "app-user-toggle")
})

test("Tab wraps inside the open drawer", () => {
  setViewport(false)
  mount()

  click("app-sidebar-toggle")
  click("app-user-toggle")
  assert.equal(focused(), "app-user-settings")

  key("Tab")
  assert.equal(focused(), "nav-companies")

  key("Tab", {shiftKey: true})
  assert.equal(focused(), "app-user-settings")
})

test("following a link in the drawer closes it", () => {
  setViewport(false)
  mount()

  click("app-sidebar-toggle")
  $("nav-companies").dispatchEvent(new MouseEvent("click", {bubbles: true, cancelable: true}))

  assert.equal(inert("app-sidebar"), true)
})

test("widening to desktop closes the drawer and releases the page", () => {
  setViewport(false)
  mount()

  click("app-sidebar-toggle")
  viewport.cross(true)

  assert.equal($("app-shell").dataset.sidebarMode, "desktop")
  assert.equal(inert("app-sidebar"), false)
  assert.equal(inert("app-content"), false)
  assert.equal($("app-sidebar").getAttribute("role"), "navigation")
})

test("on desktop the toggle folds the sidebar to a rail and remembers it", () => {
  mount()
  assert.equal($("app-sidebar").style.width, "240px")

  click("app-sidebar-toggle")

  assert.equal($("app-shell").dataset.sidebarRail, "true")
  assert.equal($("app-sidebar").style.width, "56px")
  assert.equal($("app-sidebar-toggle").getAttribute("aria-expanded"), "false")
  assert.equal(localStorage.getItem("sidebarRail"), "1")

  shell.hook.destroyed()
  mount()
  assert.equal($("app-sidebar").style.width, "56px")
})

test("dragging the edge resizes the sidebar within bounds and remembers the width", () => {
  mount()
  const drag = (from, to) => {
    $("app-sidebar-drag").dispatchEvent(new MouseEvent("mousedown", {bubbles: true, button: 0, clientX: from}))
    window.dispatchEvent(new MouseEvent("mousemove", {clientX: to}))
    window.dispatchEvent(new MouseEvent("mouseup", {}))
  }

  drag(240, 300)
  assert.equal($("app-sidebar").style.width, "300px")
  assert.equal(localStorage.getItem("sidebarWidth"), "300")

  drag(300, 900)
  assert.equal($("app-sidebar").style.width, "360px")

  drag(360, 20)
  assert.equal($("app-shell").dataset.sidebarRail, "true")
  assert.equal(localStorage.getItem("sidebarRail"), "1")
  assert.equal(localStorage.getItem("sidebarWidth"), "360")
})

test("a navigation branch opens, closes, and stays as it was left", () => {
  mount()
  assert.equal($("nav-children-admin").hidden, true)

  click("nav-toggle-admin")
  assert.equal($("nav-children-admin").hidden, false)
  assert.equal($("nav-toggle-admin").getAttribute("aria-expanded"), "true")

  shell.hook.destroyed()
  mount()
  assert.equal($("nav-children-admin").hidden, false)
})

test("pinning a navigation item lists it above the navigation and presses its pin", () => {
  mount()
  assert.equal($("app-pinned").hidden, true)

  click("nav-pin-companies")

  assert.equal($("app-pinned").hidden, false)
  assert.deepEqual(pinnedLinks(), ["/companies"])
  assert.equal($("app-pinned-items").querySelector("a").getAttribute("data-phx-link"), "redirect")
  assert.equal($("nav-pin-companies").getAttribute("aria-pressed"), "true")
  assert.equal($("nav-pin-companies").title, "Unpin Companies to sidebar")
  assert.deepEqual(storedPins(), [{id: "nav-companies"}])

  click("nav-pin-companies")
  assert.equal($("app-pinned").hidden, true)
  assert.deepEqual(storedPins(), [])
})

test("a page-header pin saves the record's label and URL beside the navigation pins", () => {
  mount()

  click("company-pin")

  const link = $("app-pinned-items").querySelector("a")
  assert.equal(link.pathname, "/companies/1")
  assert.equal(link.textContent, "Administration / Companies / Acme")
  assert.equal(link.getAttribute("data-phx-link"), "redirect")
  assert.equal($("company-pin").getAttribute("aria-pressed"), "true")
  assert.deepEqual(storedPins(), [{label: "Administration / Companies / Acme", url: "/companies/1"}])

  $("app-pinned-items").querySelector("[data-nav-unpin]").click()
  assert.deepEqual(pinnedLinks(), [])
  assert.equal($("company-pin").getAttribute("aria-pressed"), "false")
})

test("a stored pin is read back in every saved form, and a foreign or unknown one is dropped", () => {
  localStorage.setItem(
    "sidebarPinnedItems",
    JSON.stringify([
      "nav-companies",
      {id: "nav-companies"},
      {label: "Acme", url: "/companies/1?tab=users"},
      {label: "Elsewhere", url: "https://attacker.test/phish"},
      {id: "nav-removed"},
      {label: "", url: "/blank"},
    ])
  )

  mount()

  assert.deepEqual(pinnedLinks(), ["/companies", "/companies/1?tab=users"])
  assert.deepEqual(storedPins(), [{id: "nav-companies"}, {label: "Acme", url: "/companies/1?tab=users"}])
})

test("a server patch that resets a pin's pressed state is corrected on update (#685)", () => {
  localStorage.setItem("sidebarPinnedItems", JSON.stringify([{label: "Administration / Companies / Acme", url: "/companies/1"}]))
  mount()
  assert.equal($("company-pin").getAttribute("aria-pressed"), "true")

  // LiveView re-renders the title pin with the server's default.
  $("company-pin").setAttribute("aria-pressed", "false")
  $("company-pin").title = "Pin this company to sidebar"
  shell.hook.updated()

  assert.equal($("company-pin").getAttribute("aria-pressed"), "true")
  assert.equal($("company-pin").title, "Unpin this company to sidebar")
  assert.equal($("app-pinned-items").querySelectorAll("a").length, 1)
})

test("dragging a pinned row onto another reorders and saves the pins", () => {
  localStorage.setItem(
    "sidebarPinnedItems",
    JSON.stringify([{id: "nav-companies"}, {label: "Acme", url: "/companies/1"}])
  )
  mount()

  const rows = () => [...$("app-pinned-items").querySelectorAll("[data-pinned-item]")]
  const dragEvent = (type, target) => {
    const event = new Event(type, {bubbles: true, cancelable: true})
    event.dataTransfer = {setData() {}}
    target.dispatchEvent(event)
  }

  const [first, second] = rows()
  dragEvent("dragstart", second)
  dragEvent("dragover", first)
  assert.equal(first.dataset.pinnedDropTarget, "true")
  dragEvent("drop", first)

  assert.deepEqual(pinnedLinks(), ["/companies/1", "/companies"])
  assert.deepEqual(storedPins(), [{label: "Acme", url: "/companies/1"}, {id: "nav-companies"}])
})
