// tiling.js: the Ctrl+. tiling mode, the focus it moves, the split handles,
// dragging a tile onto another, and the size report. Frames are outside
// happy-dom, so the bridge into a frame's document, the URL and title
// report, and Back-button behaviour are checked in a browser
// (apps/base/ui/AGENTS.md "Hook tests").
import {test, beforeEach, afterEach} from "node:test"
import assert from "node:assert/strict"
import Tiling from "../js/tiling.js"
import {mountHook, render, focused, settle} from "./support/hook.mjs"

let control

// The tile chrome `<.tile_controls>` renders: a grip and the menu trigger,
// floating over the tile. `data-title` and `data-follow` are the host's.
function workspace({focusedTile = "t1", count = 2} = {}) {
  return render(
    `<div id="app-shell">
       <span id="app-mode" hidden role="status"></span>
       <div id="workspace" phx-hook="Tiling" data-focused="${focusedTile}" data-monocle="false"
            data-tile-count="${count}">
         <p id="workspace-announcement" role="status"></p>
         <div id="workspace-tiles">
           <div id="tile-t1" class="workspace-tile" data-tile="t1" data-title="Companies"
                data-focused="${focusedTile === "t1"}">
             <div id="tile-t1-controls" data-tile-controls>
               <span id="tile-t1-controls-grip" data-tile-grip></span>
               <button type="button" id="tile-t1-controls-menu" data-tile-menu aria-expanded="false">Menu</button>
             </div>
           </div>
           <div id="tile-t2" class="workspace-tile" data-tile="t2" data-title="Users"
                data-focused="${focusedTile === "t2"}">
             <div id="tile-t2-controls" data-tile-controls>
               <span id="tile-t2-controls-grip" data-tile-grip></span>
               <button type="button" id="tile-t2-controls-menu" data-tile-menu aria-expanded="false">Menu</button>
             </div>
           </div>
           <div id="split-s3" role="separator" tabindex="0" data-split="s3" data-direction="h"
                data-rect="0 0 1 1" data-place="left: 50%; top: 0%; height: 100%"></div>
         </div>
       </div>
     </div>`,
    "workspace"
  )
}

function press(key, init = {}) {
  window.dispatchEvent(new KeyboardEvent("keydown", {key, bubbles: true, cancelable: true, ...init}))
}

const leader = () => press(".", {ctrlKey: true})
const mode = () => document.getElementById("app-mode")
const events = () => control.pushes.map(({event, payload}) => ({event, payload}))

beforeEach(() => {
  control = mountHook(Tiling, workspace())
  control.pushes.length = 0 // the size report on mount is not under test here
})

afterEach(() => control.hook.destroyed())

test("Ctrl+. enters tiling mode, names it in the status bar, and leaves it again", () => {
  assert.equal(mode().hidden, true)

  leader()
  assert.equal(control.hook.el.dataset.mode, "tiling")
  assert.equal(mode().hidden, false)
  assert.equal(mode().textContent, "Tiling")

  leader()
  assert.equal(control.hook.el.dataset.mode, "off")
  assert.equal(mode().hidden, true)
  assert.equal(mode().textContent, "")
})

test("outside the mode, the keys are the page's own", () => {
  press("h")
  press("q")
  press("1")

  assert.deepEqual(events(), [])
})

test("in the mode, directions focus, shifted directions move, and letters run the tile operations", () => {
  leader()
  press("l")
  press("ArrowDown")
  press("J", {shiftKey: true})
  press("s")
  press("f")
  press("t")
  press("m")
  press("o")
  press("3")
  press("q")

  assert.deepEqual(events(), [
    {event: "focus-direction", payload: {side: "right"}},
    {event: "focus-direction", payload: {side: "down"}},
    {event: "move-tile", payload: {id: "t1", side: "down"}},
    {event: "swap-tile", payload: {id: "t1", side: "down"}},
    {event: "toggle-monocle", payload: {id: "t1"}},
    {event: "toggle-split", payload: {id: "t1"}},
    {event: "make-master", payload: {id: "t1"}},
    {event: "open-alone", payload: {id: "t1"}},
    {event: "open-layout", payload: {n: 3}},
    {event: "close-tile", payload: {id: "t1"}},
  ])
})

test("w asks to follow, and to stop on a tile the server marks as following", () => {
  leader()
  press("w")
  document.getElementById("tile-t1").dataset.follow = "on"
  press("w")

  assert.deepEqual(events(), [
    {event: "follow-tile", payload: {id: "t1"}},
    {event: "unfollow-tile", payload: {id: "t1"}},
  ])
})

test("a mode key is consumed so the page under it never sees it", () => {
  leader()
  const event = new KeyboardEvent("keydown", {key: "q", bubbles: true, cancelable: true})
  window.dispatchEvent(event)

  assert.equal(event.defaultPrevented, true)
})

test("r enters resize, arrows move the nearest divider, Escape steps back out one level", () => {
  leader()
  press("r")
  assert.equal(mode().textContent, "Resize")

  press("ArrowLeft")
  press("l")
  press("q")
  assert.deepEqual(events(), [
    {event: "resize-step", payload: {side: "left"}},
    {event: "resize-step", payload: {side: "right"}},
  ])

  press("Escape")
  assert.equal(control.hook.el.dataset.mode, "tiling")
  press("Escape")
  assert.equal(control.hook.el.dataset.mode, "off")
})

test("an expanded sidebar branch does not hold Escape", () => {
  leader()
  document.getElementById("app-shell").insertAdjacentHTML(
    "afterbegin",
    '<button type="button" id="app-sidebar-toggle" aria-expanded="true">Toggle sidebar</button>' +
      '<button type="button" data-nav-toggle aria-expanded="true">Administration</button>'
  )

  press("Escape")

  assert.equal(control.hook.el.dataset.mode, "off")
})

test("Escape leaves an open menu alone", () => {
  leader()
  document.getElementById("tile-t1-controls-menu").setAttribute("aria-expanded", "true")

  press("Escape")

  assert.equal(control.hook.el.dataset.mode, "tiling")
})

test("n leaves the mode and opens the picker, however many tiles are open", () => {
  leader()
  press("n")
  assert.deepEqual(events(), [{event: "open-picker", payload: {}}])
  assert.equal(control.hook.el.dataset.mode, "off")

  control.hook.destroyed()
  control = mountHook(Tiling, workspace({count: 40}))
  control.pushes.length = 0

  leader()
  press("n")
  assert.deepEqual(events(), [{event: "open-picker", payload: {}}])
})

const pointer = (type, target, init) =>
  target.dispatchEvent(new PointerEvent(type, {bubbles: true, cancelable: true, button: 0, ...init}))

// happy-dom has no layout, so the tile under the pointer is stood in for.
function tileUnderPointer(id) {
  document.elementFromPoint = () => (id ? document.getElementById(`tile-${id}`) : null)
}

test("dragging a tile's grip onto another tile marks the target and swaps on release", () => {
  const grip = document.getElementById("tile-t1-controls-grip")
  tileUnderPointer("t2")

  pointer("pointerdown", grip, {clientX: 10, clientY: 10})
  window.dispatchEvent(new PointerEvent("pointermove", {clientX: 12, clientY: 10}))
  assert.equal(control.hook.el.dataset.tileDrag, undefined, "a wobble is not a drag")

  window.dispatchEvent(new PointerEvent("pointermove", {clientX: 300, clientY: 10}))
  assert.equal(control.hook.el.dataset.tileDrag, "t1")
  assert.equal(document.getElementById("tile-t1").dataset.dragging, "true")
  assert.equal(document.getElementById("tile-t2").dataset.dropTarget, "true")
  assert.equal(document.documentElement.style.cursor, "grabbing")

  window.dispatchEvent(new PointerEvent("pointerup", {clientX: 300, clientY: 10}))
  assert.deepEqual(events(), [{event: "swap-tile", payload: {id: "t1", with: "t2"}}])
  assert.equal(document.getElementById("tile-t2").hasAttribute("data-drop-target"), false)
  assert.equal(document.getElementById("tile-t1").hasAttribute("data-dragging"), false)
  assert.equal(document.documentElement.style.cursor, "")
  assert.match(document.getElementById("workspace-announcement").textContent, /Swapped Companies and Users/)

  // The click the release produces is not a press of the control under it.
  const click = new MouseEvent("click", {bubbles: true, cancelable: true})
  document.getElementById("tile-t2-controls-menu").dispatchEvent(click)
  assert.equal(click.defaultPrevented, true)
})

test("a drag released over its own tile or over nothing swaps nothing", () => {
  const grip = document.getElementById("tile-t1-controls-grip")

  tileUnderPointer("t1")
  pointer("pointerdown", grip, {clientX: 10, clientY: 10})
  window.dispatchEvent(new PointerEvent("pointermove", {clientX: 300, clientY: 10}))
  assert.equal(document.getElementById("tile-t1").hasAttribute("data-drop-target"), false)
  window.dispatchEvent(new PointerEvent("pointerup", {clientX: 300, clientY: 10}))

  tileUnderPointer(null)
  pointer("pointerdown", grip, {clientX: 10, clientY: 10})
  window.dispatchEvent(new PointerEvent("pointermove", {clientX: 300, clientY: 10}))
  window.dispatchEvent(new PointerEvent("pointerup", {clientX: 300, clientY: 10}))

  assert.deepEqual(events(), [])
})

test("the tile menu is not a grip, and a press that never travels swaps nothing", () => {
  tileUnderPointer("t2")

  pointer("pointerdown", document.getElementById("tile-t1-controls-menu"), {clientX: 10, clientY: 10})
  window.dispatchEvent(new PointerEvent("pointermove", {clientX: 300, clientY: 10}))
  window.dispatchEvent(new PointerEvent("pointerup", {clientX: 300, clientY: 10}))
  assert.equal(control.hook.el.dataset.tileDrag, undefined)

  pointer("pointerdown", document.getElementById("tile-t1-controls-grip"), {clientX: 10, clientY: 10})
  window.dispatchEvent(new PointerEvent("pointerup", {clientX: 10, clientY: 10}))
  const click = new MouseEvent("click", {bubbles: true, cancelable: true})
  document.getElementById("tile-t1-controls-menu").dispatchEvent(click)

  assert.equal(click.defaultPrevented, false)
  assert.deepEqual(events(), [])
})

test("a press on the chrome of a tile that is not focused focuses it", () => {
  pointer("pointerdown", document.getElementById("tile-t1-controls-menu"))
  assert.deepEqual(events(), [], "the focused tile is not focused again")

  pointer("pointerdown", document.getElementById("tile-t2-controls-menu"))
  assert.deepEqual(events(), [{event: "focus-tile", payload: {id: "t2"}}])
})

test("after a keyboard move, focus follows the tile the server focused", () => {
  leader()
  press("l")

  control.hook.el.dataset.focused = "t2"
  document.getElementById("tile-t2").dataset.focused = "true"
  control.hook.updated()

  assert.equal(focused(), "tile-t2-controls-menu")
})

test("a server patch that did not follow a keyboard move leaves focus alone", () => {
  document.getElementById("tile-t1-controls-menu").focus()

  control.hook.el.dataset.focused = "t2"
  control.hook.updated()

  assert.equal(focused(), "tile-t1-controls-menu")
})

test("a patch that moves tiles and dividers repaints both to the server's geometry", () => {
  const tile = document.getElementById("tile-t2")
  const handle = document.getElementById("split-s3")
  tile.dataset.place = "left: 50%; top: 0%; width: 50%; height: 100%"
  control.hook.updated()

  tile.dataset.place = "left: 70%; top: 0%; width: 30%; height: 100%"
  handle.dataset.place = "left: 70%; top: 0%; height: 100%"
  assert.equal(tile.style.left, "50%")
  control.hook.updated()

  assert.equal(tile.style.left, "70%")
  assert.equal(tile.style.width, "30%")
  assert.equal(handle.style.left, "70%")
})

test("arrow keys on a focused handle nudge its divider", () => {
  const handle = document.getElementById("split-s3")
  handle.focus()
  handle.dispatchEvent(new KeyboardEvent("keydown", {key: "ArrowRight", bubbles: true, cancelable: true}))
  handle.dispatchEvent(new KeyboardEvent("keydown", {key: "x", bubbles: true, cancelable: true}))

  assert.deepEqual(events(), [{event: "nudge-split", payload: {id: "s3", side: "right"}}])
})

test("dragging a handle follows the pointer and pushes the ratio once on release", () => {
  const tiles = document.getElementById("workspace-tiles")
  tiles.getBoundingClientRect = () => ({left: 100, top: 0, width: 1000, height: 500})
  const handle = document.getElementById("split-s3")
  assert.equal(handle.style.left, "50%", "placed from data-place on mount")
  assert.equal(control.hook.el.dataset.placed, "true")

  handle.dispatchEvent(new PointerEvent("pointerdown", {button: 0, bubbles: true, cancelable: true}))
  window.dispatchEvent(new PointerEvent("pointermove", {clientX: 800, clientY: 10}))
  assert.equal(handle.style.left, "70%")
  assert.equal(document.documentElement.style.cursor, "col-resize")

  window.dispatchEvent(new PointerEvent("pointermove", {clientX: 100, clientY: 10}))
  assert.equal(handle.style.left, "10%")

  window.dispatchEvent(new PointerEvent("pointerup", {}))
  assert.equal(document.documentElement.style.cursor, "")
  assert.deepEqual(events(), [{event: "resize-split", payload: {id: "s3", ratio: 0.1}}])
})

test("the workspace reports its size on mount", () => {
  control.hook.destroyed()
  const el = workspace()
  document.getElementById("workspace-tiles").getBoundingClientRect = () => ({
    left: 0,
    top: 0,
    width: 1280.4,
    height: 720,
  })

  control = mountHook(Tiling, el)

  assert.deepEqual(events(), [{event: "viewport", payload: {w: 1280, h: 720}}])
})

test("a tile-navigate event sends the named frame to the page, and nothing else", () => {
  const tile = document.getElementById("tile-t2")
  tile.insertAdjacentHTML("beforeend", '<iframe id="tile-t2-page" data-tile-frame="t2" src="/users"></iframe>')
  const frame = document.getElementById("tile-t2-page")
  const moves = []
  // happy-dom gives a frame no window; the hook then falls back to `src`.
  Object.defineProperty(frame, "contentWindow", {
    value: {location: {replace: (path) => moves.push(path)}},
  })

  control.serverEvent("tile-navigate", {id: "t2", path: "/users/92?ws=abcdefghijklmnop"})
  assert.deepEqual(moves, ["/users/92?ws=abcdefghijklmnop"])

  control.serverEvent("tile-navigate", {id: "t1", path: "/users/92"})
  control.serverEvent("tile-navigate", {id: "t2", path: "https://example.test/x"})
  control.serverEvent("tile-navigate", {id: "t2", path: "//example.test/x"})
  assert.equal(moves.length, 1)
  assert.equal(frame.getAttribute("src"), "/users")
})

test("a frame is named after the title its tile reports", () => {
  const tile = document.getElementById("tile-t2")
  tile.insertAdjacentHTML(
    "beforeend",
    '<iframe id="tile-t2-page" data-tile-frame="t2" title="/users"></iframe>'
  )

  control.hook.updated()
  assert.equal(document.getElementById("tile-t2-page").title, "Users")

  tile.dataset.title = "Grace Hopper"
  control.hook.updated()
  assert.equal(document.getElementById("tile-t2-page").title, "Grace Hopper")
})

test("a frame whose window is out of reach takes the path as its source", () => {
  const tile = document.getElementById("tile-t2")
  tile.insertAdjacentHTML("beforeend", '<iframe id="tile-t2-page" data-tile-frame="t2" src="/users"></iframe>')
  const frame = document.getElementById("tile-t2-page")
  Object.defineProperty(frame, "contentWindow", {
    get() {
      throw new Error("cross-origin")
    },
  })

  control.serverEvent("tile-navigate", {id: "t2", path: "/users/92"})
  assert.equal(frame.getAttribute("src"), "/users/92")
})

test("a frame reports its page on load and again when its title is patched", async () => {
  const tile = document.getElementById("tile-t2")
  tile.insertAdjacentHTML("beforeend", '<iframe id="tile-t2-page" data-tile-frame="t2"></iframe>')
  const frame = document.getElementById("tile-t2-page")
  const doc = document.implementation.createHTMLDocument("")
  doc.head.appendChild(doc.createElement("title")).textContent = "Users · Business application platform"
  const win = new EventTarget()
  win.location = {pathname: "/users", search: "?ws=abcdefghijklmnop"}
  Object.defineProperty(frame, "contentWindow", {value: win})
  Object.defineProperty(frame, "contentDocument", {value: doc})

  control.hook.attachFrame(frame)
  assert.deepEqual(events(), [
    {event: "tile-navigated", payload: {id: "t2", path: "/users?ws=abcdefghijklmnop", title: "Users · Business application platform"}},
  ])

  win.location.pathname = "/users/92"
  win.location.search = ""
  win.dispatchEvent(new Event("phx:page-loading-stop"))
  doc.querySelector("title").textContent = "Grace Hopper · Business application platform"
  await settle()

  assert.deepEqual(events().slice(1), [
    {event: "tile-navigated", payload: {id: "t2", path: "/users/92", title: "Users · Business application platform"}},
    {event: "tile-navigated", payload: {id: "t2", path: "/users/92", title: "Grace Hopper · Business application platform"}},
  ])
})
