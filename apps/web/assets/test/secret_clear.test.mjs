import {test} from "node:test"
import assert from "node:assert/strict"
import SecretClear from "../js/secret_clear.js"
import {mountHook, render} from "./support/hook.mjs"

test("clear empties the submitted property without triggering form validation", () => {
  const button = render(
    `<form><input id="api-key" name="api_key" type="password" value="••••••••">
     <button id="api-key-clear" type="button" data-input-id="api-key">Clear API key</button></form>`,
    "api-key-clear"
  )
  const {hook} = mountHook(SecretClear, button)
  const input = document.getElementById("api-key")
  let inputs = 0
  input.addEventListener("input", () => inputs++)

  button.click()

  assert.equal(input.value, "")
  assert.equal(new FormData(button.form).get("api_key"), "")
  assert.equal(inputs, 0)
  assert.equal(document.activeElement, input)
  hook.destroyed()
})
