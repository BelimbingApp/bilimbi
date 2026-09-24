// Mounts a LiveView hook against real DOM, standing in for the LiveView
// runtime at the three seams the hooks use: pushing an event, and running a
// JS command either from the socket (`liveSocket.execJS`) or from the hook
// (`this.js().exec`). `exec` is returned too, to run a command the markup
// binds to a click, which LiveView would run.
//
// A JS command is the JSON the server rendered into the markup. The ops the
// hooks run are applied to the DOM here the way LiveView applies them, so a
// test observes what a person would: an attribute written, focus moved, an
// event sent. An op this does not model fails the test rather than being
// skipped, so a markup change cannot turn an assertion vacuous.

export function mountHook(Hook, el) {
  const pushes = []
  const run = (encoded) => applyCommands(encoded, pushes)

  const hook = Object.create(Hook)
  hook.el = el
  hook.pushEvent = (event, payload, reply) => pushes.push({event, payload, reply})
  hook.pushEventTo = (target, event, payload, reply) => pushes.push({target, event, payload, reply})
  hook.liveSocket = {execJS: (_el, encoded) => run(encoded)}
  hook.js = () => ({exec: run})

  hook.mounted()

  return {hook, pushes, exec: run}
}

function applyCommands(encoded, pushes) {
  for (const [op, args] of JSON.parse(encoded)) {
    const targets = args.to ? [...document.querySelectorAll(args.to)] : []

    switch (op) {
      case "set_attr":
        for (const target of targets) target.setAttribute(...args.attr)
        break

      case "toggle_attr": {
        const [name, on, off] = args.attr
        for (const target of targets) {
          target.setAttribute(name, target.getAttribute(name) === on ? off : on)
        }
        break
      }

      case "focus":
        targets[0]?.focus()
        break

      case "push":
        pushes.push({event: args.event, payload: args.value ?? {}})
        break

      case "hide":
        for (const target of targets) target.style.display = "none"
        break

      default:
        throw new Error(`the hook harness does not model the "${op}" command`)
    }
  }
}

// MutationObserver callbacks and zero-delay timeouts run after the current
// task, as in a browser. Awaiting this lets both land before asserting.
export const settle = () => new Promise((resolve) => setTimeout(resolve, 0))

// `innerHTML` for one fixture, returning the element with `id`.
export function render(html, id) {
  document.body.innerHTML = html
  return document.getElementById(id)
}

// Which element has focus, by id (or tag when it has none). Assertions compare
// this rather than the elements themselves: a failed comparison of two DOM
// nodes makes Node print the whole document graph, which never finishes.
export function focused() {
  const el = document.activeElement
  return el?.id || el?.tagName || null
}
