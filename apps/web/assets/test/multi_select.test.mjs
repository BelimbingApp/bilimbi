// multi_select.js: closing the `<.multi_select>` list on Escape and when focus
// leaves the field. Opening and closing are the wrapper's own JS commands,
// and the trigger's `aria-expanded` is the one record of open.
import {test, beforeEach, afterEach} from "node:test"
import assert from "node:assert/strict"
import MultiSelectDismiss from "../js/multi_select.js"
import {focused, mountHook, render, settle} from "./support/hook.mjs"

// The commands `multi_select/1` renders for `id="roles-filter"`.
const DISMISS = '[["set_attr",{"to":"#roles-filter","attr":["aria-expanded","false"]}]]'
const ESCAPE =
  '[["set_attr",{"to":"#roles-filter","attr":["aria-expanded","false"]}],["focus",{"to":"#roles-filter"}]]'

let field

beforeEach(() => {
  const wrapper = render(
    `<input id="page-search" type="search">
     <div id="roles-filter-wrapper" phx-hook="MultiSelectDismiss"
          data-dismiss='${DISMISS}' data-escape='${ESCAPE}'>
       <button id="roles-filter" type="button" aria-expanded="false"
               aria-controls="roles-filter-options">Any role</button>
       <div id="roles-filter-options" tabindex="-1">
         <input type="checkbox" id="roles-filter-option-admin" value="admin">
         <input type="checkbox" id="roles-filter-option-clerk" value="clerk">
       </div>
     </div>
     <button id="apply" type="button">Apply</button>`,
    "roles-filter-wrapper"
  )
  field = mountHook(MultiSelectDismiss, wrapper)
})

afterEach(() => field.hook.destroyed())

const trigger = () => document.getElementById("roles-filter")
const expanded = () => trigger().getAttribute("aria-expanded")
const byId = (id) => document.getElementById(id)

// The trigger's click command writes the attribute; the hook hears it after
// the current task, as a MutationObserver does in a browser.
async function open() {
  trigger().setAttribute("aria-expanded", "true")
  await settle()
}

const key = (name, target = document.activeElement ?? document.body) =>
  target.dispatchEvent(new KeyboardEvent("keydown", {key: name, bubbles: true}))

const press = (el) => el.dispatchEvent(new PointerEvent("pointerdown", {bubbles: true}))
const release = () => window.dispatchEvent(new PointerEvent("pointerup"))

test("Escape does nothing to a closed list", () => {
  byId("roles-filter-option-admin").focus()
  key("Escape")

  assert.equal(expanded(), "false")
  assert.equal(focused(), "roles-filter-option-admin")
})

test("Escape from inside the field closes the list and returns focus to the trigger", async () => {
  await open()
  byId("roles-filter-option-clerk").focus()

  key("Escape")

  assert.equal(expanded(), "false")
  assert.equal(focused(), "roles-filter")
})

test("Escape with focus left on the page still closes a list opened by mouse", async () => {
  // Safari and macOS Firefox do not focus a pressed button.
  await open()
  assert.equal(focused(), "BODY")

  key("Escape")

  assert.equal(expanded(), "false")
  assert.equal(focused(), "BODY")
})

test("Escape typed in another field closes the list without taking the caret", async () => {
  await open()
  byId("page-search").focus()

  key("Escape")

  assert.equal(expanded(), "false")
  assert.equal(focused(), "page-search")
})

test("other keys leave the list open", async () => {
  await open()
  byId("roles-filter-option-admin").focus()

  key("ArrowDown")
  key("a")

  assert.equal(expanded(), "true")
})

test("once closed, Escape stops reaching the field", async () => {
  await open()
  trigger().setAttribute("aria-expanded", "false")
  await settle()

  // Reopen and press Escape inside the same task, before the hook has heard
  // of the reopening: only a listener left behind by the close could act.
  trigger().setAttribute("aria-expanded", "true")
  key("Escape")

  assert.equal(expanded(), "true")
})

test("Tab moving between the trigger and its options keeps the list open", async () => {
  await open()
  trigger().focus()

  byId("roles-filter-option-admin").focus()
  byId("roles-filter-option-clerk").focus()

  assert.equal(expanded(), "true")
})

test("focus leaving the field closes the list", async () => {
  await open()
  byId("roles-filter-option-clerk").focus()

  byId("apply").focus()

  assert.equal(expanded(), "false")
  assert.equal(focused(), "apply")
})

test("the window losing focus closes the list", async () => {
  await open()
  trigger().focus()

  trigger().blur()

  assert.equal(expanded(), "false")
})

test("a press inside the field does not close the list on the blur it causes", async () => {
  // In Safari the press blurs the focused option without focusing the button
  // pressed. Closing then would let the same click reopen the list.
  await open()
  byId("roles-filter-option-admin").focus()

  press(trigger())
  byId("roles-filter-option-admin").blur()
  assert.equal(expanded(), "true")

  // That blur spent the press: the next departure is a real one.
  release()
  byId("roles-filter-option-clerk").focus()
  byId("roles-filter-option-clerk").blur()
  assert.equal(expanded(), "false")
})

test("a press released away from the field does not swallow a later departure", async () => {
  await open()
  byId("roles-filter-option-admin").focus()

  // Pressed inside, dragged off and released: no click, no blur.
  press(byId("roles-filter-option-admin"))
  release()

  byId("apply").focus()
  assert.equal(expanded(), "false")
})

test("a destroyed field stops listening to the page", async () => {
  await open()
  field.hook.destroyed()
  field.hook.destroyed = () => {}

  key("Escape")
  byId("roles-filter-option-admin").focus()
  byId("apply").focus()

  assert.equal(expanded(), "true")
})
