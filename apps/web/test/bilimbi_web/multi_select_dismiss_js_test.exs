defmodule BilimbiWeb.MultiSelectDismissJsTest do
  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/multi_select.js", __DIR__)

  test "the open list survives focus moving inside the field and closes when it leaves" do
    source = @hook |> File.read!() |> Base.encode64()

    script = """
    import assert from 'node:assert/strict'
    const {default: MultiSelectDismiss} = await import('data:text/javascript;base64,#{source}')

    const trigger = {}
    const option = {}
    const elsewhere = {}
    const listeners = {}
    const execed = []
    const el = {
      dataset: {dismiss: '[["add_class",{"names":["hidden"],"to":"#roles-filter-options"}]]'},
      contains: node => node === trigger || node === option,
      addEventListener(type, fn) { listeners[type] = fn },
      removeEventListener(type, fn) { if (listeners[type] === fn) delete listeners[type] },
    }
    const hook = {el, js: () => ({exec: payload => execed.push(payload)}), ...MultiSelectDismiss}
    hook.mounted()

    // Tabbing from the trigger onto an option is still inside the field.
    listeners.focusout({relatedTarget: option})
    assert.deepEqual(execed, [])

    // Tabbing past the last option lands outside it, where no LiveView
    // binding of ours would ever fire again.
    listeners.focusout({relatedTarget: elsewhere})
    assert.deepEqual(execed, [el.dataset.dismiss])

    // The window losing focus reports no new target at all.
    listeners.focusout({relatedTarget: null})
    assert.deepEqual(execed, [el.dataset.dismiss, el.dataset.dismiss])

    // Safari and macOS Firefox blur without focusing the control being
    // pressed, so a press on the trigger arrives as focus leaving the field.
    // Closing there would let the click that press belongs to reopen the
    // list, leaving the trigger unable to close it at all.
    listeners.pointerdown({})
    listeners.focusout({relatedTarget: null})
    assert.equal(execed.length, 2)

    // That blur spends the press: the next one is a real one.
    listeners.focusout({relatedTarget: null})
    assert.equal(execed.length, 3)

    // A press with no focus to take spends itself on its own click.
    listeners.pointerdown({})
    listeners.click({})
    listeners.focusout({relatedTarget: null})
    assert.equal(execed.length, 4)

    hook.destroyed()
    assert.equal(listeners.focusout, undefined)
    assert.equal(listeners.pointerdown, undefined)
    assert.equal(listeners.click, undefined)
    console.log('ok')
    """

    assert {"ok\n", 0} =
             System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
  end
end
