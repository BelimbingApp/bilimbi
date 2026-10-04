// Shared in-flight bookkeeping for the inline editors. A new inline control
// announces a commit through these helpers rather than copying `aria-busy`,
// the `[data-role="saving"]` mark, and the `pushEventTo` payload.

function savingElement(hook) {
  return hook.el.querySelector('[data-role="saving"]')
}

export function markSaving(hook) {
  hook.el.setAttribute("aria-busy", "true")
  savingElement(hook)?.classList.remove("hidden")
}

export function settle(hook) {
  hook.el.removeAttribute("aria-busy")
  savingElement(hook)?.classList.add("hidden")
}

// `value` is the text the owner asked to store. The payload's field name and
// event come from the element's `data-field` and `data-save-event`. The
// reply calls `hook.settle()`, which clears this in-flight mark and any
// editor-specific wait.
export function commit(hook, {value}) {
  const field = hook.el.dataset.field || "value"
  const saveEvent = hook.el.dataset.saveEvent || "save"

  markSaving(hook)
  hook.pushEventTo(hook.el, saveEvent, {id: hook.el.dataset.id, [field]: value}, () =>
    hook.settle()
  )
}

export function focusTrigger(hook) {
  hook.triggerEl?.focus()
}
