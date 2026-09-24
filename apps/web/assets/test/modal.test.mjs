// modal.js: the bridge between the server's <dialog> and the browser's modal
// behaviour. See the comment at the top of the hook.
import {test, beforeEach} from "node:test"
import assert from "node:assert/strict"
import Modal from "../js/modal.js"
import {focused, mountHook, render, settle} from "./support/hook.mjs"

// happy-dom has no top layer and does not make the page inert, so whether a
// dialog is modal is not observable on the element. The browser gives focus
// containment and the inert page to a dialog shown with showModal(), so that
// call is what is recorded here: a dialog shown with show() would be open and
// contain nothing.
const shownModally = new WeakSet()
const showModal = HTMLDialogElement.prototype.showModal
HTMLDialogElement.prototype.showModal = function () {
  shownModally.add(this)
  return showModal.call(this)
}

const CANCEL = '[["push",{"event":"cancel_edit"}]]'

beforeEach(() => {
  render(
    `<main>
       <button id="edit-open" type="button">Edit</button>
       <button id="export" type="button">Export</button>
     </main>`,
    "edit-open"
  )
})

// The server renders the dialog, already `open`, once the workflow starts.
function openDialog() {
  document.body.insertAdjacentHTML(
    "beforeend",
    `<dialog id="edit-dialog" open phx-hook="Modal" data-cancel='${CANCEL}' tabindex="-1">
       <h2 id="edit-dialog-title">Edit company</h2>
       <button id="edit-save" type="button">Save</button>
     </dialog>`
  )
  const dialog = document.getElementById("edit-dialog")
  return {dialog, ...mountHook(Modal, dialog)}
}

// The server ends the workflow by removing the element; LiveView then
// destroys the hook.
function closeDialog({dialog, hook}) {
  dialog.remove()
  hook.destroyed()
}

// A pointer press as a browser that does not focus buttons on click delivers
// it: the press reaches the button, focus stays where it was.
const press = (el) => el.dispatchEvent(new PointerEvent("pointerdown", {bubbles: true}))

// A keyboard activation: the control holds focus when the key goes down.
function keyActivate(el) {
  el.focus()
  el.dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))
}

test("the server's open dialog becomes a modal one without asking the server to close it", async () => {
  const opened = openDialog()

  assert.equal(opened.dialog.open, true)
  assert.ok(shownModally.has(opened.dialog), "the dialog was not shown with showModal()")

  // Reopening an already-open dialog as modal closes it first; that close
  // must not read as the person dismissing it.
  await settle()
  assert.deepEqual(opened.pushes, [])
})

test("Escape asks the server to close and leaves the dialog open until it does", () => {
  const {dialog, pushes} = openDialog()

  // A browser answers Escape on a modal dialog with a cancelable `cancel`.
  const escape = new Event("cancel", {cancelable: true})
  dialog.dispatchEvent(escape)

  assert.equal(escape.defaultPrevented, true)
  assert.equal(dialog.open, true)
  assert.deepEqual(pushes, [{event: "cancel_edit", payload: {}}])
})

test("a close the browser carries out anyway still tells the server", async () => {
  const {dialog, pushes} = openDialog()

  dialog.close()
  await settle()

  assert.deepEqual(pushes, [{event: "cancel_edit", payload: {}}])
})

test("focus returns to the clicked control even when the click left focus on the page", () => {
  const opener = document.getElementById("edit-open")

  press(opener)
  assert.equal(focused(), "BODY")

  const opened = openDialog()
  closeDialog(opened)

  assert.equal(focused(), opener.id)
})

test("focus returns to the control activated from the keyboard", () => {
  const opener = document.getElementById("edit-open")

  keyActivate(opener)
  const opened = openDialog()
  document.getElementById("edit-save").focus()
  closeDialog(opened)

  assert.equal(focused(), opener.id)
})

test("an earlier click elsewhere does not steal focus from a keyboard opener", () => {
  const opener = document.getElementById("edit-open")

  // Some time ago the person clicked Export, which opened nothing.
  press(document.getElementById("export"))

  // Now they open the dialog from the keyboard.
  keyActivate(opener)
  const opened = openDialog()
  closeDialog(opened)

  assert.equal(focused(), opener.id)
})

test("each dialog returns focus to its own opener, not a previous dialog's", () => {
  const opener = document.getElementById("edit-open")

  press(opener)
  closeDialog(openDialog())

  // The next dialog is opened from the keyboard, from another control.
  const exporter = document.getElementById("export")
  keyActivate(exporter)
  closeDialog(openDialog())

  assert.equal(focused(), exporter.id)
})

test("an opener removed while the dialog was open is left alone", () => {
  const opener = document.getElementById("edit-open")

  press(opener)
  const opened = openDialog()
  opener.remove()
  document.getElementById("edit-save").focus()
  closeDialog(opened)

  assert.notEqual(focused(), "edit-open")
})
