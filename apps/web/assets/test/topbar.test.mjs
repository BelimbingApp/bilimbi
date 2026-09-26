// vendor/topbar.js paints the page-loading bar on a canvas. The trickle and
// the fade are requestAnimationFrame loops, so the prefers-reduced-motion
// rule in css/app.css cannot reach them. The marked check in the vendor file
// is what keeps that bar still.
import {describe, test, beforeEach, afterEach} from "node:test"
import assert from "node:assert/strict"
import topbar from "../vendor/topbar.js"

const REDUCED = "(prefers-reduced-motion: reduce)"

function preferReducedMotion(reduced) {
  window.matchMedia = (query) => ({
    matches: reduced && query === REDUCED,
    media: query,
    addEventListener() {},
    removeEventListener() {},
  })
}

let frames

function installAnimationFrames() {
  frames = []
  let id = 0
  window.requestAnimationFrame = (callback) => {
    id += 1
    frames.push(callback)
    return id
  }
  window.cancelAnimationFrame = () => {}
}

function stubCanvas() {
  HTMLCanvasElement.prototype.getContext = () => ({
    shadowBlur: 0,
    shadowColor: "",
    lineWidth: 0,
    strokeStyle: "",
    createLinearGradient() {
      return {addColorStop() {}}
    },
    beginPath() {},
    moveTo() {},
    lineTo() {},
    stroke() {},
  })
}

function canvas() {
  return document.querySelector("canvas")
}

describe("topbar progress under prefers-reduced-motion", {concurrency: false}, () => {
  beforeEach(() => {
    stubCanvas()
    installAnimationFrames()
    document.body.replaceChildren()
  })

  afterEach(() => {
    preferReducedMotion(true)
    topbar.hide()
    document.body.replaceChildren()
  })

  test("reduced motion shows one static full-width bar and schedules no frame", () => {
    preferReducedMotion(true)

    topbar.show()

    assert.equal(canvas().style.display, "block")
    assert.equal(Number(canvas().style.opacity), 1)
    assert.equal(topbar.progress(), 1)
    assert.equal(frames.length, 0)
  })

  test("reduced motion removes the bar immediately", () => {
    preferReducedMotion(true)
    topbar.show()

    topbar.hide()

    assert.equal(canvas().style.display, "none")
    assert.equal(Number(canvas().style.opacity), 0)
    assert.equal(frames.length, 0)
  })

  test("ordinary motion trickles the bar forward on a frame", () => {
    preferReducedMotion(false)

    topbar.show()

    assert.equal(frames.length, 1)
    assert.ok(topbar.progress() > 0 && topbar.progress() < 1)
    assert.equal(canvas().style.display, "block")
  })

  test("ordinary motion fades the bar out across frames", () => {
    preferReducedMotion(false)
    topbar.show()
    const shown = frames.length

    topbar.hide()

    assert.ok(frames.length > shown)
    assert.equal(canvas().style.display, "block")
  })
})
