import {test, afterEach} from "node:test"
import assert from "node:assert/strict"
import CodeInput from "../js/code_input.js"
import {mountHook, render, focused} from "./support/hook.mjs"
let control
function mount(value = "") {
  const el = render(`<div id="code" data-code-length="8">
    <label for="user-code">Device code</label>
    <input id="user-code" name="device[user_code]" value="${value}" aria-describedby="hint">
    <div id="boxes" data-code-boxes hidden aria-hidden="true">
      ${Array.from({length: 8}, (_, i) => `<span data-code-index="${i}"></span>`).join("")}
    </div><p id="hint">Eight characters</p></div>`, "code")
  control = mountHook(CodeInput, el)
  return el.querySelector("input")
}
afterEach(() => control?.hook.destroyed())
function inputValue(input, value, caret) {
  input.value = value
  input.setSelectionRange(caret, caret)
  input.dispatchEvent(new Event("input", {bubbles: true}))
}
function paste(input, text) {
  const event = new Event("paste", {bubbles: true, cancelable: true})
  event.clipboardData = {getData: () => text}
  input.dispatchEvent(event)
}
test("prefill paints eight boxes with one labelled field", () => {
  const input = mount("ABCD-EF23")
  assert.equal(input.value, "ABCDEF23")
  assert.equal(document.querySelectorAll("input").length, 1)
  assert.equal(document.querySelector("label").htmlFor, input.id)
  assert.equal(document.getElementById("boxes").hidden, false)
  assert.equal(document.getElementById("boxes").getAttribute("aria-hidden"), "true")
  assert.deepEqual(control.hook.boxes.map(b => b.textContent), [..."ABCDEF23"])
})
test("typing advances; native backspace and arrows move the active box back", () => {
  const input = mount()
  input.focus()
  inputValue(input, "a", 1)
  assert.equal(input.value, "A")
  assert.equal(control.hook.boxes[1].hasAttribute("data-active"), true)
  inputValue(input, "", 0)
  assert.equal(control.hook.boxes[0].hasAttribute("data-active"), true)
  inputValue(input, "ABCD", 4)
  input.setSelectionRange(3, 3)
  input.dispatchEvent(new Event("keyup"))
  assert.equal(control.hook.boxes[3].hasAttribute("data-active"), true)
  assert.equal(focused(), "user-code")
})
test("whole code paste fills every box with or without a separator, even mid-code", () => {
  const input = mount("ZZZZ-ZZZZ")
  input.focus()
  for (const text of ["abcd-ef23", "ABCDEF23"]) {
    input.setSelectionRange(2, 2)
    paste(input, text)
    assert.equal(input.value, "ABCDEF23")
    assert.equal(input.selectionStart, 8)
    assert.deepEqual(control.hook.boxes.map(b => b.textContent), [..."ABCDEF23"])
  }
})
test("clicking a box positions the caret and selection can be replaced", () => {
  const input = mount("ABCD-EF23")
  control.hook.boxes[3].click()
  assert.equal(focused(), "user-code")
  assert.equal(input.selectionStart, 3)
  input.setSelectionRange(2, 4)
  paste(input, "xy")
  assert.equal(input.value, "ABXYEF23")
})
test("a server patch preserves the enhanced control and paints the new value", () => {
  const input = mount()
  input.className = "rounded-md"
  input.value = "ABCD-EF23"
  control.hook.updated()
  assert.equal(input.classList.contains("opacity-0"), true)
  assert.equal(input.value, "ABCDEF23")
  assert.deepEqual(control.hook.boxes.map(b => b.textContent), [..."ABCDEF23"])
})
