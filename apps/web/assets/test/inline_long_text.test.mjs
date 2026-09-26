import {test} from "node:test"
import assert from "node:assert/strict"
import InlineLongText from "../js/inline_long_text.js"
import {focused, mountHook, render} from "./support/hook.mjs"

function mountEditor({value = "First line\nSecond line", allowEmpty = false} = {}) {
  const el = render(
    `<div id="description" phx-hook="InlineLongText" data-id="42" data-field="description"
          data-save-event="save_field" data-cancel-event="cancel_edit_field" data-value="${value}"
          ${allowEmpty ? "data-allow-empty" : ""}>
       <button id="description-display" data-role="trigger" type="button">Description</button>
       <textarea id="description-input" data-role="input" name="description">${value}</textarea>
       <span data-role="saving" class="hidden">Saving…</span>
     </div>
     <button id="elsewhere" type="button">Elsewhere</button>`,
    "description"
  )
  return {el, ...mountHook(InlineLongText, el)}
}

const textarea = () => document.getElementById("description-input")
const key = (el, name) => {
  const event = new KeyboardEvent("keydown", {key: name, bubbles: true, cancelable: true})
  el.dispatchEvent(event)
  return event
}

test("leaving the textarea commits its unmodified multiline value to the owner and announces saving", () => {
  const {el, pushes} = mountEditor()
  textarea().focus()
  textarea().value = "Updated first line\nUpdated second line"
  document.getElementById("elsewhere").focus()

  assert.equal(pushes.length, 1)
  assert.equal(pushes[0].target, el)
  assert.equal(pushes[0].event, "save_field")
  assert.deepEqual(pushes[0].payload, {id: "42", description: "Updated first line\nUpdated second line"})
  assert.equal(el.getAttribute("aria-busy"), "true")
  assert.equal(document.querySelector('[data-role="saving"]').classList.contains("hidden"), false)
})

test("Escape cancels and returns focus without a later blur commit", () => {
  const {el, pushes} = mountEditor()
  textarea().focus()
  textarea().value = "discard this"
  const event = key(textarea(), "Escape")

  assert.equal(event.defaultPrevented, true)
  assert.equal(pushes.length, 1)
  assert.equal(pushes[0].event, "cancel_edit_field")
  assert.deepEqual(pushes[0].payload, {})
  assert.equal(focused(), "description-display")
})

test("an unchanged value cancels instead of sending a write", () => {
  const {pushes} = mountEditor()
  textarea().focus()
  document.getElementById("elsewhere").focus()

  assert.equal(pushes.length, 1)
  assert.equal(pushes[0].event, "cancel_edit_field")
})

test("a blank value is rejected unless the owner allows clearing the field", () => {
  const {pushes} = mountEditor()
  textarea().focus()
  textarea().value = "  \n "
  document.getElementById("elsewhere").focus()
  assert.equal(pushes[0].event, "cancel_edit_field")

  const clearable = mountEditor({value: "Text", allowEmpty: true})
  textarea().focus()
  textarea().value = ""
  document.getElementById("elsewhere").focus()
  assert.deepEqual(clearable.pushes[0].payload, {id: "42", description: ""})
})

test("the server reply clears the in-flight state and uses the patched stored value", () => {
  const {el, pushes, hook} = mountEditor()
  textarea().focus()
  textarea().value = "Updated"
  document.getElementById("elsewhere").focus()
  pushes[0].reply({})

  assert.equal(el.hasAttribute("aria-busy"), false)
  assert.equal(document.querySelector('[data-role="saving"]').classList.contains("hidden"), true)

  el.dataset.value = "Server value"
  el.querySelector('[data-role="trigger"]').focus()
  hook.updated()
  assert.equal(textarea().value, "Server value")
})
