// flash_auto_dismiss.js: a success flash dismisses itself after the delay
// the server wrote on it, by running its own close command.
import {test, beforeEach, afterEach, mock} from "node:test"
import assert from "node:assert/strict"
import FlashAutoDismiss from "../js/flash_auto_dismiss.js"
import {mountHook, render} from "./support/hook.mjs"

// The close command `flash_group/1` renders on the success flash.
const CLOSE =
  '[["push",{"value":{"key":"success"},"event":"lv:clear-flash"}],["hide",{"time":200,"to":"#flash-success","transition":[["transition-all","ease-in","duration-200"],["opacity-100","translate-y-0","sm:scale-100"],["opacity-0","translate-y-4","sm:translate-y-0","sm:scale-95"]]}]]'

beforeEach(() => mock.timers.enable({apis: ["setTimeout"]}))
afterEach(() => mock.timers.reset())

function mountFlash({delay = "8000", click = CLOSE} = {}) {
  const el = render(
    `<div id="flash-success" role="status" phx-hook="FlashAutoDismiss"
          ${delay === null ? "" : `data-auto-dismiss-ms="${delay}"`}
          ${click === null ? "" : `phx-click='${click}'`}>Company saved.</div>`,
    "flash-success"
  )
  return {el, ...mountHook(FlashAutoDismiss, el)}
}

const cleared = (pushes) => pushes.filter(({event}) => event === "lv:clear-flash")

test("the flash stays for the whole delay", () => {
  const {el, pushes} = mountFlash()

  mock.timers.tick(7999)

  assert.deepEqual(pushes, [])
  assert.notEqual(el.style.display, "none")
})

test("after the delay the flash is cleared on the server and hidden, as a click would", () => {
  const {el, pushes} = mountFlash()

  mock.timers.tick(8000)

  assert.deepEqual(cleared(pushes), [{event: "lv:clear-flash", payload: {key: "success"}}])
  assert.equal(el.style.display, "none")
})

test("a flash removed before its delay is never dismissed again", () => {
  const {el, pushes, hook} = mountFlash()

  mock.timers.tick(3000)
  el.remove()
  hook.destroyed()
  mock.timers.tick(10000)

  assert.deepEqual(pushes, [])
})

test("a flash without a usable delay stays until dismissed", () => {
  for (const delay of [null, "0", "-5", "soon"]) {
    const {pushes} = mountFlash({delay})

    mock.timers.tick(60000)

    assert.deepEqual(pushes, [], `delay ${JSON.stringify(delay)} dismissed the flash`)
  }
})

test("a flash with no close command is left alone", () => {
  const {el} = mountFlash({click: null})

  assert.doesNotThrow(() => mock.timers.tick(8000))
  assert.notEqual(el.style.display, "none")
})
