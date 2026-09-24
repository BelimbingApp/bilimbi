// dashboard_sort.js: drag-to-reorder for the dashboard widget grid. The hook
// only reports the order after a drop; the LiveView validates and saves it.
import {test, beforeEach, afterEach} from "node:test"
import assert from "node:assert/strict"
import DashboardSort from "../js/dashboard_sort.js"
import {mountHook, render} from "./support/hook.mjs"

let grid

beforeEach(() => {
  const el = render(
    `<div id="dashboard-widgets" phx-hook="DashboardSort">
       <div id="widget-companies" data-widget-id="companies">
         <button id="drag-companies" draggable="true" data-role="drag-handle">Drag</button>
       </div>
       <div id="widget-users" data-widget-id="users">
         <button id="drag-users" draggable="true" data-role="drag-handle">Drag</button>
       </div>
       <div id="widget-audit" data-widget-id="audit">
         <button id="drag-audit" draggable="true" data-role="drag-handle">Drag</button>
       </div>
     </div>`,
    "dashboard-widgets"
  )
  grid = mountHook(DashboardSort, el)
})

afterEach(() => grid.hook.destroyed())

const $ = (id) => document.getElementById(id)
const order = () => [...document.querySelectorAll("[data-widget-id]")].map((el) => el.dataset.widgetId)

// happy-dom lays nothing out, so each widget reports a 100px-high box stacked
// in DOM order, which is enough for the hook's upper-or-lower-half choice.
function layout() {
  document.querySelectorAll("[data-widget-id]").forEach((el, index) => {
    el.getBoundingClientRect = () => ({top: index * 100, height: 100})
  })
}

function drag(type, target, init = {}) {
  const event = new MouseEvent(type, {bubbles: true, cancelable: true, ...init})
  event.dataTransfer = {setData() {}}
  target.dispatchEvent(event)
  return event
}

test("dropping a widget over the lower half of another moves it after that one and reports the order", () => {
  drag("dragstart", $("drag-companies"))
  assert.equal($("widget-companies").classList.contains("opacity-40"), true)

  layout()
  const over = drag("dragover", $("widget-users"), {clientY: 175})
  assert.equal(over.defaultPrevented, true)
  drag("drop", $("widget-users"))
  drag("dragend", $("widget-companies"))

  assert.deepEqual(order(), ["users", "companies", "audit"])
  assert.equal($("widget-companies").classList.contains("opacity-40"), false)
  assert.deepEqual(grid.pushes.map(({event, payload}) => ({event, payload})), [
    {event: "reorder-widgets", payload: {ids: ["users", "companies", "audit"]}},
  ])
})

test("dropping over the upper half of a widget moves the dragged one before it", () => {
  drag("dragstart", $("drag-audit"))
  layout()
  drag("dragover", $("widget-companies"), {clientY: 20})
  drag("dragend", $("widget-audit"))

  assert.deepEqual(order(), ["audit", "companies", "users"])
  assert.deepEqual(grid.pushes[0].payload, {ids: ["audit", "companies", "users"]})
})

test("a drag that did not start on a widget moves nothing and sends nothing", () => {
  const over = drag("dragover", $("widget-users"), {clientY: 175})
  drag("dragend", $("dashboard-widgets"))

  assert.equal(over.defaultPrevented, false)
  assert.deepEqual(order(), ["companies", "users", "audit"])
  assert.deepEqual(grid.pushes, [])
})
