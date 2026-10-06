import {test, afterEach} from "node:test"
import assert from "node:assert/strict"
import FlexTable from "../js/flex_table.js"
import {focused, mountHook, render} from "./support/hook.mjs"

// The markup `flex_table/1` renders, cut down to what the hook reads: the
// chips and headings it drags, the add bar it walks, and a bar it sizes.
function table(suggestions = "") {
  return `
    <div id="grid" phx-hook="FlexTable" data-event="grid" data-mode="normal" class="flex-table">
      <div id="grid-toolbar">
        <ul id="grid-chips">
          <li id="grid-chip-name" data-chip="name" draggable="true">Name</li>
          <li id="grid-chip-count" data-chip="users:count" draggable="true">Count</li>
          <li id="grid-chip-code" data-chip="code" draggable="true">Code</li>
        </ul>
        <form id="grid-add-column">
          <input id="grid-add-column-input" name="add" type="search" />
          ${suggestions}
        </form>
        <div id="grid-zoom" role="group">
          <button type="button" id="grid-zoom-out" data-zoom-op="zoom" data-dir="out" disabled><span class="icon"></span></button>
          <span id="grid-zoom-level">20 px</span>
          <button type="button" id="grid-zoom-in" data-zoom-op="zoom" data-dir="in"><span class="icon"></span></button>
          <button type="button" id="grid-zoom-compact" data-zoom-op="zoom_preset" data-preset="compact" aria-pressed="true"><svg></svg>Compact</button>
          <button type="button" id="grid-zoom-normal" data-zoom-op="zoom_preset" data-preset="normal" aria-pressed="false"><svg></svg>Normal</button>
        </div>
        <button type="button" id="grid-reset" phx-click="grid" phx-value-op="reset">Reset to default columns</button>
      </div>
      <div id="grid-viewport" data-viewport tabindex="0">
        <table><thead><tr>
          <th id="grid-head-name" data-header="name" draggable="true">Name</th>
          <th id="grid-head-count" data-header="users:count" draggable="true">Count</th>
          <th id="grid-head-code" data-header="code" draggable="true">Code</th>
        </tr></thead>
        <tbody><tr><td><span class="bar-track"><span data-bar="63"></span></span></td></tr></tbody></table>
      </div>
    </div>`
}

const suggestions = `
  <ul id="grid-suggestions" role="listbox">
    <li role="option"><button type="button" id="grid-suggest-company-name">Company › Name</button></li>
    <li role="option"><button type="button" id="grid-suggest-users_count">Users › Count</button></li>
  </ul>`

let control

afterEach(() => control && control.hook.destroyed())

function drag(from, to, clientX) {
  const dataTransfer = {data: {}, setData(k, v) { this.data[k] = v }, getData(k) { return this.data[k] }, effectAllowed: "", dropEffect: ""}
  from.dispatchEvent(Object.assign(new Event("dragstart", {bubbles: true}), {dataTransfer}))
  to.dispatchEvent(Object.assign(new Event("dragover", {bubbles: true, cancelable: true}), {dataTransfer, clientX}))
  to.dispatchEvent(Object.assign(new Event("drop", {bubbles: true, cancelable: true}), {dataTransfer, clientX}))
  from.dispatchEvent(new Event("dragend", {bubbles: true}))
}

function key(element, name) {
  element.dispatchEvent(new KeyboardEvent("keydown", {key: name, bubbles: true, cancelable: true}))
}

test("a bar takes its width from data-bar, since the CSP refuses inline style", () => {
  control = mountHook(FlexTable, render(table(), "grid"))
  assert.equal(document.querySelector("[data-bar]").style.width, "63%")
})

test("dropping a chip on another pushes a move before or after it", () => {
  control = mountHook(FlexTable, render(table(), "grid"))
  // happy-dom lays nothing out, so every box sits at 0: a pointer left of it
  // drops before, a pointer right of it drops after.
  drag(document.getElementById("grid-chip-code"), document.getElementById("grid-chip-name"), -1)
  assert.deepEqual(control.pushes.at(-1), {event: "grid", payload: {op: "move", spec: "code", before: "name"}, reply: undefined})
  drag(document.getElementById("grid-chip-name"), document.getElementById("grid-chip-count"), 1)
  assert.deepEqual(control.pushes.at(-1).payload, {op: "move", spec: "name", before: "code"})
})

test("a heading drags like its chip, and a drop past the last column moves to the end", () => {
  control = mountHook(FlexTable, render(table(), "grid"))
  drag(document.getElementById("grid-head-name"), document.getElementById("grid-head-code"), 1)
  assert.deepEqual(control.pushes.at(-1).payload, {op: "move", spec: "name", before: null})
  assert.equal(document.querySelectorAll("[data-dragging], [data-drop]").length, 0)
})

test("dropping a column on itself pushes nothing", () => {
  control = mountHook(FlexTable, render(table(), "grid"))
  const chip = document.getElementById("grid-chip-name")
  drag(chip, chip, 1)
  assert.equal(control.pushes.length, 0)
})

test("every press on a zoom step is pushed, however fast, with its direction", () => {
  control = mountHook(FlexTable, render(table(), "grid"))
  const taller = document.getElementById("grid-zoom-in")
  // LiveView's own `phx-click` drops a click on a control still waiting for
  // its last reply; three presses here are three steps, none acknowledged.
  taller.click()
  taller.click()
  taller.querySelector(".icon").click()
  assert.deepEqual(control.pushes.map((push) => push.payload), [
    {op: "zoom", dir: "in"},
    {op: "zoom", dir: "in"},
    {op: "zoom", dir: "in"},
  ])
})

test("a press on a preset lands straight after a press on the other one", () => {
  control = mountHook(FlexTable, render(table(), "grid"))
  const compact = document.getElementById("grid-zoom-compact")
  const normal = document.getElementById("grid-zoom-normal")
  compact.click()
  compact.click()
  normal.click()
  compact.querySelector("svg").dispatchEvent(new Event("click", {bubbles: true}))
  assert.deepEqual(control.pushes.map((push) => push.payload), [
    {op: "zoom_preset", preset: "compact"},
    {op: "zoom_preset", preset: "compact"},
    {op: "zoom_preset", preset: "normal"},
    {op: "zoom_preset", preset: "compact"},
  ])
})

test("the step at the end of the range pushes nothing, and neither does any other control", () => {
  control = mountHook(FlexTable, render(table(), "grid"))
  document.getElementById("grid-zoom-out").click()
  document.getElementById("grid-zoom-out").querySelector(".icon").dispatchEvent(new Event("click", {bubbles: true}))
  document.getElementById("grid-zoom-level").click()
  // The reset is the server's own `phx-click`; the hook leaves it alone.
  document.getElementById("grid-reset").click()
  assert.equal(control.pushes.length, 0)
})

test("the arrow keys walk the add bar's suggestions and back to the input", () => {
  control = mountHook(FlexTable, render(table(suggestions), "grid"))
  const input = document.getElementById("grid-add-column-input")
  input.focus()
  key(input, "ArrowDown")
  assert.equal(focused(), "grid-suggest-company-name")
  key(document.activeElement, "ArrowDown")
  assert.equal(focused(), "grid-suggest-users_count")
  key(document.activeElement, "ArrowDown")
  assert.equal(focused(), "grid-suggest-users_count", "the last suggestion is the end")
  key(document.activeElement, "ArrowUp")
  key(document.activeElement, "ArrowUp")
  assert.equal(focused(), "grid-add-column-input")
})

test("Escape in the add bar clears what was typed", () => {
  control = mountHook(FlexTable, render(table(suggestions), "grid"))
  const input = document.getElementById("grid-add-column-input")
  input.value = "comp"
  let changed = 0
  input.addEventListener("input", () => changed++)
  input.focus()
  key(input, "Escape")
  assert.equal(input.value, "")
  assert.equal(changed, 1, "the form hears the cleared value")
})
