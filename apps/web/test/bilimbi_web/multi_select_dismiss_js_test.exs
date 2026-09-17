defmodule BilimbiWeb.MultiSelectDismissJsTest do
  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/multi_select.js", __DIR__)

  defp harness(body) do
    source = @hook |> File.read!() |> Base.encode64()

    """
    import assert from 'node:assert/strict'

    const listeners = {}
    const onWindow = {}
    globalThis.window = {
      addEventListener(type, fn) { onWindow[type] = fn },
      removeEventListener(type, fn) { if (onWindow[type] === fn) delete onWindow[type] },
    }

    globalThis.document = {activeElement: null}

    const observers = []
    globalThis.MutationObserver = class {
      constructor(fn) { this.fn = fn; observers.push(this) }
      observe(node, options) { this.node = node; this.options = options }
      disconnect() { this.stopped = true }
    }

    const {default: MultiSelectDismiss} = await import('data:text/javascript;base64,#{source}')

    const trigger = {
      attrs: {'aria-expanded': 'false'},
      getAttribute(name) { return name in this.attrs ? this.attrs[name] : null },
    }

    // Opening and closing are LiveView JS commands on the markup: they land
    // as an attribute write on the trigger, which is what the hook watches.
    // Only an observer registered on that element hears it, so a hook wired
    // to any other node goes deaf here exactly as it would in a browser.
    const expand = (value) => {
      trigger.attrs['aria-expanded'] = value
      observers.forEach(o => { if (!o.stopped && o.node === trigger) o.fn([], o) })
    }

    const option = {}
    const elsewhere = {}
    const execed = []
    const el = {
      // The two commands the wrapper really publishes: closing writes the one
      // record of open and nothing else, and only Escape adds the refocus.
      dataset: {
        dismiss: '[["set_attr",{"to":"#roles-filter","attr":["aria-expanded","false"]}]]',
        escape: '[["set_attr",{"to":"#roles-filter","attr":["aria-expanded","false"]}],["focus",{"to":"#roles-filter"}]]',
      },
      contains: node => node === trigger || node === option,
      querySelector: sel => (sel === '[aria-expanded]' ? trigger : null),
      addEventListener(type, fn) { listeners[type] = fn },
      removeEventListener(type, fn) { if (listeners[type] === fn) delete listeners[type] },
    }
    const hook = {el, js: () => ({exec: payload => execed.push(payload)}), ...MultiSelectDismiss}
    hook.mounted()

    #{body}

    console.log('ok')
    """
  end

  defp run(script) do
    System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
  end

  test "Escape closes the list from wherever focus is, and only while it is open" do
    script =
      harness("""
      // A closed field watches no keys, so every other Escape handler on the
      // page keeps the ones it already had.
      assert.equal(onWindow.keydown, undefined)

      // The attribute the list's open state actually lives on, on the element
      // that actually carries it.
      assert.equal(observers[0].node, trigger)
      assert.deepEqual(observers[0].options, {attributeFilter: ['aria-expanded']})

      expand('true')
      assert.equal(typeof onWindow.keydown, 'function')

      // Safari and macOS Firefox open the list by mouse without focusing the
      // trigger, so the key arrives with focus still on `body`: nothing under
      // the field would ever see it, and the list must still close.
      onWindow.keydown({key: 'Escape'})
      assert.deepEqual(execed, [el.dataset.dismiss])

      // A window listener also hears Escape typed into a search box further
      // up the page. Closing there must not yank the caret onto this trigger.
      document.activeElement = elsewhere
      onWindow.keydown({key: 'Escape'})
      assert.deepEqual(execed, [el.dataset.dismiss, el.dataset.dismiss])

      // Focus already inside the field is the one case that restores it, so a
      // keyboard user is left on the control they just dismissed.
      document.activeElement = option
      onWindow.keydown({key: 'Escape'})
      assert.deepEqual(execed, [el.dataset.dismiss, el.dataset.dismiss, el.dataset.escape])

      // Every other key is the page's to handle.
      onWindow.keydown({key: 'a'})
      assert.equal(execed.length, 3)

      // Closing again -- by the command Escape just ran, the trigger, or a
      // click away -- stops the listening.
      expand('false')
      assert.equal(onWindow.keydown, undefined)

      // A patch re-applying the same sticky attribute is not a state change.
      expand('false')
      expand('true')
      expand('true')
      assert.equal(typeof onWindow.keydown, 'function')

      hook.destroyed()
      assert.deepEqual(Object.keys(listeners), [])
      assert.deepEqual(Object.keys(onWindow), [])
      assert.equal(observers[0].stopped, true)
      """)

    assert {"ok\n", 0} = run(script)
  end

  test "the open list survives focus moving inside the field and closes when it leaves" do
    script =
      harness("""
      expand('true')

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

      // A press released off the field, a right-click, or a touch that became
      // a scroll never becomes a click here -- but the release still arrives,
      // so the press cannot outlive it and swallow a later Tab away.
      listeners.pointerdown({})
      onWindow.pointerup({})
      listeners.focusout({relatedTarget: null})
      assert.equal(execed.length, 4)

      listeners.pointerdown({})
      onWindow.pointercancel({})
      listeners.focusout({relatedTarget: null})
      assert.equal(execed.length, 5)

      hook.destroyed()
      assert.deepEqual(Object.keys(listeners), [])
      assert.deepEqual(Object.keys(onWindow), [])
      """)

    assert {"ok\n", 0} = run(script)
  end
end
