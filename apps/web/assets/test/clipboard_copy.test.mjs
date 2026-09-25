// clipboard_copy.js: a click on a `[data-copy-text]` tile copies its text and
// reports to the server whether the browser accepted the write.
import {test, beforeEach, afterEach} from "node:test"
import assert from "node:assert/strict"
import ClipboardCopy from "../js/clipboard_copy.js"
import {mountHook, render, settle} from "./support/hook.mjs"

const original = Object.getOwnPropertyDescriptor(navigator, "clipboard")
let control
let written

function useClipboard(clipboard) {
  Object.defineProperty(navigator, "clipboard", {value: clipboard, configurable: true})
}

beforeEach(() => {
  written = []
  useClipboard({writeText: async (text) => void written.push(text)})

  const catalog = render(
    `<div id="icon-catalog" phx-hook="ClipboardCopy" data-copy-event="icon-copied">
       <button type="button" id="icon-tile-create" data-copy-text="create">
         <span id="icon-tile-create-name">create</span>
       </button>
       <button type="button" id="icon-catalog-clear">Clear filter</button>
     </div>`,
    "icon-catalog"
  )
  control = mountHook(ClipboardCopy, catalog)
})

afterEach(() => {
  control.hook.destroyed()
  if (original) Object.defineProperty(navigator, "clipboard", original)
  else delete navigator.clipboard
})

const click = (id) => document.getElementById(id).click()

test("a tile copies its name and reports the write as done", async () => {
  click("icon-tile-create-name")
  await settle()

  assert.deepEqual(written, ["create"])
  assert.deepEqual(control.pushes, [{event: "icon-copied", payload: {text: "create", copied: true}, reply: undefined}])
})

test("a refused write is reported as not copied", async () => {
  useClipboard({writeText: () => Promise.reject(new Error("NotAllowedError"))})

  click("icon-tile-create")
  await settle()

  assert.deepEqual(control.pushes, [{event: "icon-copied", payload: {text: "create", copied: false}, reply: undefined}])
})

test("a browser without the Clipboard API is reported as not copied", async () => {
  useClipboard(undefined)

  click("icon-tile-create")
  await settle()

  assert.deepEqual(control.pushes, [{event: "icon-copied", payload: {text: "create", copied: false}, reply: undefined}])
})

test("a click on anything else in the catalogue copies nothing", async () => {
  click("icon-catalog-clear")
  await settle()

  assert.deepEqual(written, [])
  assert.deepEqual(control.pushes, [])
})
