import {test} from "node:test"
import assert from "node:assert/strict"
import SecretStored from "../js/secret_stored.js"
import SecretClear from "../js/secret_clear.js"
import {mountHook, render} from "./support/hook.mjs"

test("stored value is absent initially, appears only for the server's window, then is erased", async () => {
  const input = render('<input id="stored" type="password" value="••••••••">', "stored")
  const {hook, serverEvent} = mountHook(SecretStored, input)

  assert.equal(input.value, "••••••••")
  assert.equal(input.type, "password")

  serverEvent("secret:reveal", {id: "different", value: "ignored", duration_ms: 10})
  assert.equal(input.value, "••••••••")

  serverEvent("secret:reveal", {id: "stored", value: "private-example", duration_ms: 20})
  assert.equal(input.value, "private-example")
  assert.equal(input.type, "text")

  await new Promise((resolve) => setTimeout(resolve, 30))
  assert.equal(input.value, "••••••••")
  assert.equal(input.type, "password")
  hook.destroyed()
})

test("disconnect erases a value before its window ends", () => {
  const input = render('<input id="stored" type="password" value="••••••••">', "stored")
  const {hook, serverEvent} = mountHook(SecretStored, input)
  serverEvent("secret:reveal", {id: "stored", value: "private-example", duration_ms: 10_000})

  hook.destroyed()

  assert.equal(input.value, "••••••••")
  assert.equal(input.type, "password")
})

test("clearing during a reveal stays blank when the reveal window expires", async () => {
  const button = render(
    '<input id="stored" type="password" value="••••••••"><button id="clear" data-input-id="stored"></button>',
    "clear"
  )
  const input = document.getElementById("stored")
  const stored = mountHook(SecretStored, input)
  const clear = mountHook(SecretClear, button)
  stored.serverEvent("secret:reveal", {id: "stored", value: "private-example", duration_ms: 20})

  button.click()
  await new Promise((resolve) => setTimeout(resolve, 30))

  assert.equal(input.value, "")
  assert.equal(input.type, "password")
  clear.hook.destroyed()
  stored.hook.destroyed()
})
