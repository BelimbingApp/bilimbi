// inline_edit.js: the `<.inline_edit>` field. Opening the editor, committing
// on Enter or blur, cancelling on Escape, and the in-flight state between a
// commit and the server's reply. See DESIGN.md "Inline editing".
import {test} from "node:test"
import assert from "node:assert/strict"
import InlineEdit from "../js/inline_edit.js"
import {focused, mountHook, render} from "./support/hook.mjs"

// The markup `inline_edit/1` renders, trimmed to what the hook reads.
function mountField({value = "Acme Sdn Bhd", allowEmpty = false} = {}) {
  const el = render(
    `<div id="company-name" phx-hook="InlineEdit" data-id="42" data-field="name"
          data-save-event="save_field" ${allowEmpty ? "data-allow-empty" : ""}>
       <button id="company-name-trigger" type="button" data-role="trigger" aria-label="Name">
         <span data-role="text">${value || "—"}</span>
       </button>
       <input id="company-name-input" data-role="input" type="text" name="name"
              value="${value}" class="hidden" aria-label="Name">
       <span data-role="saving" class="hidden">Saving…</span>
     </div>
     <button id="elsewhere" type="button">Elsewhere</button>`,
    "company-name"
  )
  return {el, ...mountHook(InlineEdit, el)}
}

const input = () => document.getElementById("company-name-input")
const trigger = () => document.getElementById("company-name-trigger")
const saving = () => document.querySelector('[data-role="saving"]')
const shownText = () => document.querySelector('[data-role="text"]').textContent
const editing = () => !input().classList.contains("hidden")

const key = (el, name) => {
  const event = new KeyboardEvent("keydown", {key: name, bubbles: true, cancelable: true})
  el.dispatchEvent(event)
  return event
}

function type(text) {
  input().value = text
}

test("clicking the value opens the editor, focused, with the value selected", () => {
  mountField()

  trigger().click()

  assert.equal(editing(), true)
  assert.equal(focused(), "company-name-input")
  assert.deepEqual([input().selectionStart, input().selectionEnd], [0, "Acme Sdn Bhd".length])
})

test("Enter and Space on the focused value open the editor", () => {
  for (const name of ["Enter", " "]) {
    mountField()
    trigger().focus()

    const event = key(trigger(), name)

    assert.equal(event.defaultPrevented, true, `${JSON.stringify(name)} scrolled or clicked`)
    assert.equal(editing(), true)
    assert.equal(focused(), "company-name-input")
  }
})

test("Enter commits the trimmed value to the field's owner and marks it saving", () => {
  const {el, pushes} = mountField()
  trigger().click()
  type("  Acme Holdings  ")

  key(input(), "Enter")

  assert.equal(pushes.length, 1)
  assert.equal(pushes[0].target, el)
  assert.equal(pushes[0].event, "save_field")
  assert.deepEqual(pushes[0].payload, {id: "42", name: "Acme Holdings"})

  assert.equal(editing(), false)
  assert.equal(el.getAttribute("aria-busy"), "true")
  assert.equal(saving().classList.contains("hidden"), false)

  // The shown value is the server's to change; a failed save must not look
  // like a successful one.
  assert.equal(shownText(), "Acme Sdn Bhd")
})

test("Enter returns focus to the value, as Escape does", () => {
  mountField()
  trigger().click()
  type("Acme Holdings")

  key(input(), "Enter")

  // The editor is hidden now. Focus left on it drops to the page in a
  // browser, and the keyboard user loses their place in the form.
  assert.equal(focused(), "company-name-trigger")
})

test("the server's reply clears the saving state", () => {
  const {el, pushes, hook} = mountField()
  trigger().click()
  type("Acme Holdings")
  key(input(), "Enter")

  pushes[0].reply({})

  assert.equal(el.hasAttribute("aria-busy"), false)
  assert.equal(saving().classList.contains("hidden"), true)

  // A reply patch without an acknowledgement settles it the same way.
  trigger().click()
  type("Acme Group")
  key(input(), "Enter")
  hook.updated()
  assert.equal(el.hasAttribute("aria-busy"), false)
})

test("leaving the editor commits", () => {
  const {pushes} = mountField()
  trigger().click()
  type("Acme Holdings")

  document.getElementById("elsewhere").focus()

  assert.equal(pushes.length, 1)
  assert.deepEqual(pushes[0].payload, {id: "42", name: "Acme Holdings"})
  assert.equal(editing(), false)
  // Tabbing or clicking away chose where focus goes; the field keeps out of it.
  assert.equal(focused(), "elsewhere")
})

test("Escape discards the edit and returns focus to the value", () => {
  const {pushes} = mountField()
  trigger().click()
  type("Acme Holdings")

  const event = key(input(), "Escape")

  assert.equal(event.defaultPrevented, true)
  assert.deepEqual(pushes, [])
  assert.equal(editing(), false)
  assert.equal(input().value, "Acme Sdn Bhd")
  assert.equal(focused(), "company-name-trigger")
})

test("an unchanged value commits nothing", () => {
  const {el, pushes} = mountField()
  trigger().click()
  type("Acme Sdn Bhd ")

  key(input(), "Enter")

  assert.deepEqual(pushes, [])
  assert.equal(el.hasAttribute("aria-busy"), false)
})

test("an emptied required value commits nothing and puts the value back", () => {
  const {pushes} = mountField()
  trigger().click()
  type("   ")

  key(input(), "Enter")

  assert.deepEqual(pushes, [])
  assert.equal(input().value, "Acme Sdn Bhd")
})

test("an emptied value commits when the owner allows empty", () => {
  const {pushes} = mountField({allowEmpty: true})
  trigger().click()
  type("")

  key(input(), "Enter")

  assert.equal(pushes.length, 1)
  assert.deepEqual(pushes[0].payload, {id: "42", name: ""})
})

test("a patch landing mid-edit leaves the typing alone", () => {
  const {hook, pushes} = mountField()
  trigger().click()
  type("Acme Hol")

  // Another row saved; the patch rewrites this input's value attribute.
  input().setAttribute("value", "Acme Sdn Bhd")
  hook.updated()

  assert.equal(editing(), true)
  assert.equal(input().value, "Acme Hol")

  // Escape still restores what was there when editing began.
  key(input(), "Escape")
  assert.equal(input().value, "Acme Sdn Bhd")
  assert.deepEqual(pushes, [])
})

test("a patch to a closed field takes the stored value, not what was last typed", () => {
  const {hook} = mountField()
  trigger().click()
  type("Acme Holdings")
  key(input(), "Enter")

  // The server stored a normalised form of what was committed.
  input().setAttribute("value", "ACME HOLDINGS")
  hook.updated()

  trigger().click()
  assert.equal(input().value, "ACME HOLDINGS")
})
