// tab_strip.js: a tab row that does not fit scrolls inside itself. Edge
// controls appear only while a tab is outside the strip, and focusing a tab
// brings it clear of the edge that would cover it.
import {test, beforeEach, afterEach} from "node:test"
import assert from "node:assert/strict"
import TabStrip from "../js/tab_strip.js"
import {mountHook, render} from "./support/hook.mjs"

let control

function place(id, offsetLeft, offsetWidth) {
  const tab = document.getElementById(id)
  Object.defineProperty(tab, "offsetLeft", {value: offsetLeft, configurable: true})
  Object.defineProperty(tab, "offsetWidth", {value: offsetWidth, configurable: true})
}

function size(scrollWidth, clientWidth, scrollLeft = 0) {
  const scroller = document.getElementById("queues-scroller")
  Object.defineProperty(scroller, "scrollWidth", {value: scrollWidth, configurable: true})
  Object.defineProperty(scroller, "clientWidth", {value: clientWidth, configurable: true})
  scroller.scrollLeft = scrollLeft
}

beforeEach(() => {
  const strip = render(
    `<nav id="queues" aria-label="Claim queues">
       <div id="queues-scroller" data-tab-scroller>
         <a id="queues-submitted" data-tab href="#submitted" aria-current="page">Awaiting decision</a>
         <a id="queues-approved" data-tab href="#approved">Approved</a>
         <a id="queues-reimbursed" data-tab href="#reimbursed">Reimbursed</a>
         <a id="queues-rejected" data-tab href="#rejected">Rejected</a>
         <a id="queues-batches" data-tab href="#batches">Hand-off batches</a>
       </div>
       <button type="button" id="queues-scroll-start" data-tab-scroll="start" tabindex="-1" hidden>Earlier</button>
       <button type="button" id="queues-scroll-end" data-tab-scroll="end" tabindex="-1" hidden>Later</button>
     </nav>`,
    "queues"
  )

  place("queues-submitted", 0, 140)
  place("queues-approved", 144, 90)
  place("queues-reimbursed", 238, 110)
  place("queues-rejected", 352, 80)
  place("queues-batches", 436, 150)
  size(586, 320)
  control = mountHook(TabStrip, strip)
})

afterEach(() => control.hook.destroyed())

const start = () => document.getElementById("queues-scroll-start")
const end = () => document.getElementById("queues-scroll-end")
const scroller = () => document.getElementById("queues-scroller")

test("a strip that overflows shows only the edge that hides a tab", () => {
  assert.equal(start().hidden, true)
  assert.equal(end().hidden, false)
  assert.match(scroller().style.maskImage, /to left/)
})

test("scrolling to the end swaps the edge control", () => {
  scroller().scrollLeft = 266
  scroller().dispatchEvent(new Event("scroll"))

  assert.equal(start().hidden, false)
  assert.equal(end().hidden, true)
  assert.match(scroller().style.maskImage, /to right/)
})

test("a strip that fits shows no edge control", () => {
  size(320, 320)
  control.hook.sync()

  assert.equal(start().hidden, true)
  assert.equal(end().hidden, true)
  assert.equal(scroller().style.maskImage, "")
})

test("the later control scrolls the next hidden tab into view", () => {
  end().click()

  const reimbursed = document.getElementById("queues-reimbursed")
  assert.ok(reimbursed.offsetLeft + reimbursed.offsetWidth <= scroller().scrollLeft + 320 + 1)
  assert.equal(end().hidden, false)
})

test("focusing a tab that sits outside the strip scrolls it clear of the edge", () => {
  document.getElementById("queues-batches").dispatchEvent(new FocusEvent("focusin", {bubbles: true}))

  const batches = document.getElementById("queues-batches")
  assert.ok(batches.offsetLeft + batches.offsetWidth <= scroller().scrollLeft + 320 + 1)
  assert.equal(end().hidden, true)
})

test("the edge control does not take focus on press", () => {
  const event = new MouseEvent("mousedown", {bubbles: true, cancelable: true})
  end().dispatchEvent(event)
  assert.equal(event.defaultPrevented, true)
})
