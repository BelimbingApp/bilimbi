// secret_reveal.js: the show/hide control of `<.input type="password" reveal>`.
// The input's `type` is the one record of masked or shown; the control's
// name, title and glyph are derived from it.
import {test, beforeEach, afterEach} from "node:test"
import assert from "node:assert/strict"
import SecretReveal from "../js/secret_reveal.js"
import {mountHook, render, settle} from "./support/hook.mjs"

// The command the control's phx-click carries for `id="api-key"`.
const TOGGLE = '[["toggle_attr",{"to":"#api-key","attr":["type","text","password"]}]]'

let control

beforeEach(() => {
  const button = render(
    `<input type="password" id="api-key" name="api_key" value="sk-sample-0000">
     <button id="api-key-reveal" type="button" phx-hook="SecretReveal"
             aria-label="Show secret, currently hidden" aria-controls="api-key" title="Show secret"
             data-show-label="Show secret, currently hidden"
             data-hide-label="Hide secret, currently shown"
             data-show-title="Show secret" data-hide-title="Hide secret">
       <span id="api-key-reveal-show" class="grid"></span>
       <span id="api-key-reveal-hide" class="grid hidden"></span>
     </button>`,
    "api-key-reveal"
  )
  control = mountHook(SecretReveal, button)
})

afterEach(() => control.hook.destroyed())

const input = () => document.getElementById("api-key")
const button = () => document.getElementById("api-key-reveal")
const glyphShown = (which) => !document.getElementById(`api-key-reveal-${which}`).classList.contains("hidden")

function assertMasked() {
  assert.equal(input().type, "password")
  assert.equal(button().getAttribute("aria-label"), "Show secret, currently hidden")
  assert.equal(button().title, "Show secret")
  assert.equal(glyphShown("show"), true)
  assert.equal(glyphShown("hide"), false)
}

function assertShown() {
  assert.equal(input().type, "text")
  assert.equal(button().getAttribute("aria-label"), "Hide secret, currently shown")
  assert.equal(button().title, "Hide secret")
  assert.equal(glyphShown("show"), false)
  assert.equal(glyphShown("hide"), true)
}

async function toggle(times = 1) {
  for (let i = 0; i < times; i++) control.exec(TOGGLE)
  await settle()
}

test("the control starts out offering to show the masked secret", () => {
  assertMasked()
})

test("revealing and masking again keep the control's name, title and glyph truthful", async () => {
  await toggle()
  assertShown()

  await toggle()
  assertMasked()
})

test("several presses inside one frame still leave the control agreeing with the field", async () => {
  await toggle(3)
  assertShown()

  await toggle(3)
  assertMasked()
})

test("a patch that resets the control's text is corrected from the field", async () => {
  await toggle()

  // The server re-renders the static attributes; `type` is sticky and stays.
  button().setAttribute("aria-label", "Show secret, currently hidden")
  button().setAttribute("title", "Show secret")
  control.hook.updated()

  assertShown()
})

test("pressing the control with a pointer does not take focus from the field", () => {
  const press = new MouseEvent("mousedown", {bubbles: true, cancelable: true})

  button().dispatchEvent(press)

  assert.equal(press.defaultPrevented, true)
})

test("the caret survives revealing the secret while typing", async () => {
  input().focus()
  input().setSelectionRange(3, 3)

  // The hook hears the click before LiveView runs the command, and the
  // browser resets the selection when `type` changes.
  button().click()
  control.exec(TOGGLE)
  input().setSelectionRange(input().value.length, input().value.length)
  await settle()

  assert.deepEqual([input().selectionStart, input().selectionEnd], [3, 3])
  assertShown()
})

test("revealing from the keyboard leaves the caret alone", async () => {
  input().setSelectionRange(3, 3)
  button().focus()

  button().click()
  control.exec(TOGGLE)
  const end = input().value.length
  input().setSelectionRange(end, end)
  await settle()

  assert.deepEqual([input().selectionStart, input().selectionEnd], [end, end])
})

test("a removed control stops following the field", async () => {
  control.hook.destroyed()
  control.hook.destroyed = () => {}

  await toggle()

  assert.equal(button().getAttribute("aria-label"), "Show secret, currently hidden")
})
