defmodule BilimbiWeb.MultiSelectDismissJsTest do
  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/multi_select.js", __DIR__)

  test "the open list survives focus moving inside the field and closes when it leaves" do
    source = @hook |> File.read!() |> Base.encode64()

    script = """
    import assert from 'node:assert/strict'

    const listeners = {}
    const onWindow = {}
    globalThis.window = {
      addEventListener(type, fn) { onWindow[type] = fn },
      removeEventListener(type, fn) { if (onWindow[type] === fn) delete onWindow[type] },
    }

    const {default: MultiSelectDismiss} = await import('data:text/javascript;base64,#{source}')

    const trigger = {}
    const option = {}
    const elsewhere = {}
    const execed = []
    const el = {
      dataset: {
        dismiss: '[["add_class",{"names":["hidden"],"to":"#roles-filter-options"}]]',
        escape: '[["add_class",{"names":["hidden"],"to":"#roles-filter-options"}],["focus",{"to":"#roles-filter"}]]',
      },
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

    // Escape closes and returns focus, from any focus stop that bubbles here.
    listeners.keydown({key: 'Escape'})
    assert.equal(execed.at(-1), el.dataset.escape)

    // Every other key is the page's to handle.
    listeners.keydown({key: 'a'})
    assert.equal(execed.length, 3)

    // Safari and macOS Firefox blur without focusing the control being
    // pressed, so a press on the trigger arrives as focus leaving the field.
    // Closing there would let the click that press belongs to reopen the
    // list, leaving the trigger unable to close it at all.
    listeners.pointerdown({})
    listeners.focusout({relatedTarget: null})
    assert.equal(execed.length, 3)

    // That blur spends the press: the next one is a real one.
    listeners.focusout({relatedTarget: null})
    assert.equal(execed.length, 4)

    // A press released off the field, a right-click, or a touch that became a
    // scroll never becomes a click here -- but the release still arrives, so
    // the press cannot outlive it and swallow a later Tab away.
    listeners.pointerdown({})
    onWindow.pointerup({})
    listeners.focusout({relatedTarget: null})
    assert.equal(execed.length, 5)

    listeners.pointerdown({})
    onWindow.pointercancel({})
    listeners.focusout({relatedTarget: null})
    assert.equal(execed.length, 6)

    hook.destroyed()
    assert.deepEqual(Object.keys(listeners), [])
    assert.deepEqual(Object.keys(onWindow), [])
    console.log('ok')
    """

    assert {"ok\n", 0} =
             System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
  end
end
