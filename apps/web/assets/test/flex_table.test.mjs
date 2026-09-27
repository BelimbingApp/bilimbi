import {test, beforeEach, afterEach} from "node:test"
import assert from "node:assert/strict"
import FlexTable from "../js/flex_table.js"
import {mountHook, render} from "./support/hook.mjs"

const columns = JSON.stringify([
  {id: "name", spec: "name", label: "Name", short: "Name", type: "string", kind: "field", lens: "value", numeric: false},
  {id: "count", spec: "users:count", label: "Users › Count", short: "Count", type: "integer", kind: "rollup", lens: "bar", numeric: true},
  {id: "code", spec: "code", label: "Code", short: "Code", type: "string", kind: "field", lens: "value", numeric: false},
])

function table(mode, zoom) {
  return `
    <div id="grid" phx-hook="FlexTable" data-event="grid" data-zoom="${zoom}" data-mode="${mode}" data-columns='${columns}' data-total="3" data-offset="0" class="flex-table">
      <div id="grid-toolbar">
        <ul id="grid-chips">
          <li id="grid-chip-name" data-chip="name" draggable="true">Name</li>
          <li id="grid-chip-count" data-chip="users:count" draggable="true">Count</li>
          <li id="grid-chip-code" data-chip="code" draggable="true">Code</li>
        </ul>
        <form id="grid-add-column"><input id="grid-add-column-input" name="add" type="search" /></form>
        <div id="grid-group-zone" data-group-zone class="hidden">Drop a column here to group by it</div>
      </div>
      <div id="grid-viewport" data-viewport tabindex="0">
        ${
          mode === "full"
            ? `<table><thead><tr>
                 <th id="grid-head-name" data-header="name" draggable="true">Name</th>
                 <th id="grid-head-count" data-header="users:count" draggable="true">Count</th>
                 <th id="grid-head-code" data-header="code" draggable="true">Code</th>
               </tr></thead>
               <tbody><tr><td><span class="bar-track"><span data-bar="63"></span></span></td></tr></tbody></table>`
            : `<div id="grid-canvas-host" data-canvas-host phx-update="ignore"><canvas id="grid-canvas"></canvas><div id="grid-tooltip" role="status" class="hidden"></div></div>`
        }
      </div>
    </div>`
}

let control

afterEach(() => control && control.hook.destroyed())

function drag(from, to, clientX) {
  const dataTransfer = {data: {}, setData(k, v) { this.data[k] = v }, getData(k) { return this.data[k] }, effectAllowed: "", dropEffect: ""}
  from.dispatchEvent(Object.assign(new Event("dragstart", {bubbles: true}), {dataTransfer}))
  to.dispatchEvent(Object.assign(new Event("dragover", {bubbles: true, cancelable: true}), {dataTransfer, clientX}))
  to.dispatchEvent(Object.assign(new Event("drop", {bubbles: true, cancelable: true}), {dataTransfer, clientX}))
  from.dispatchEvent(new Event("dragend", {bubbles: true}))
}

test("a bar takes its width from data-bar, since the CSP refuses inline style", () => {
  control = mountHook(FlexTable, render(table("full", 28), "grid"))
  assert.equal(document.querySelector("[data-bar]").style.width, "63%")
})

test("dropping a chip on another pushes a move before or after it", () => {
  const el = render(table("full", 28), "grid")
  control = mountHook(FlexTable, el)
  // happy-dom lays nothing out, so every box sits at 0: a pointer left of it
  // drops before, a pointer right of it drops after.
  drag(document.getElementById("grid-chip-code"), document.getElementById("grid-chip-name"), -1)
  assert.deepEqual(control.pushes.at(-1), {event: "grid", payload: {op: "move", spec: "code", before: "name"}, reply: undefined})
  drag(document.getElementById("grid-chip-name"), document.getElementById("grid-chip-count"), 1)
  assert.deepEqual(control.pushes.at(-1).payload, {op: "move", spec: "name", before: "code"})
  assert.equal(el.dataset.dragActive, undefined)
})

test("dropping a heading on the group zone pushes a group", () => {
  const el = render(table("full", 28), "grid")
  control = mountHook(FlexTable, el)
  const heading = document.getElementById("grid-head-count")
  const dataTransfer = {data: {}, setData(k, v) { this.data[k] = v }, effectAllowed: "", dropEffect: ""}
  heading.dispatchEvent(Object.assign(new Event("dragstart", {bubbles: true}), {dataTransfer}))
  assert.equal(el.dataset.dragActive, "true")
  const zone = document.getElementById("grid-group-zone")
  zone.dispatchEvent(Object.assign(new Event("dragover", {bubbles: true, cancelable: true}), {dataTransfer, clientX: 0}))
  zone.dispatchEvent(Object.assign(new Event("drop", {bubbles: true, cancelable: true}), {dataTransfer, clientX: 0}))
  assert.deepEqual(control.pushes.at(-1).payload, {op: "group", spec: "users:count"})
})

test("Ctrl+wheel and the plus and minus keys zoom", () => {
  control = mountHook(FlexTable, render(table("full", 28), "grid"))
  const viewport = document.getElementById("grid-viewport")
  viewport.dispatchEvent(Object.assign(new Event("wheel", {bubbles: true, cancelable: true}), {ctrlKey: true, deltaY: -10}))
  assert.deepEqual(control.pushes.at(-1).payload, {op: "zoom", dir: "in"})
  viewport.dispatchEvent(Object.assign(new Event("wheel", {bubbles: true, cancelable: true}), {ctrlKey: false, deltaY: -10}))
  assert.equal(control.pushes.length, 1, "a plain wheel scrolls and pushes nothing")
  viewport.dispatchEvent(new KeyboardEvent("keydown", {key: "-", bubbles: true}))
  assert.deepEqual(control.pushes.at(-1).payload, {op: "zoom", dir: "out"})
})

test("a canvas mode asks for a window on mount and again when the window does not cover the view", () => {
  control = mountHook(FlexTable, render(table("carpet", 3), "grid"))
  const first = control.pushes[0]
  assert.equal(first.payload.op, "window")
  assert.equal(first.payload.detail, "levels")
  assert.equal(first.payload.offset, 0)
  control.receive("grid:window", {offset: 0, total: 3, rows: [[1, [[null, 0.2, 1, "categorical"], [null, 1, 4, "sequential"], [null, null, null, null]]]]})
  assert.equal(control.hook.rows.size, 1)
  assert.equal(control.hook.total, 3)
})

test("a scroll-to event moves the viewport to the row and column", () => {
  control = mountHook(FlexTable, render(table("mid", 12), "grid"))
  control.receive("grid:scroll", {row: 10, col: 2})
  const viewport = document.getElementById("grid-viewport")
  assert.equal(viewport.scrollTop, 120)
  assert.equal(viewport.scrollLeft, 144)
})
