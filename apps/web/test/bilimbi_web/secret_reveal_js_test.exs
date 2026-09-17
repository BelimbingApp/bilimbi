defmodule BilimbiWeb.SecretRevealJsTest do
  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/secret_reveal.js", __DIR__)

  defp harness(body) do
    source = @hook |> File.read!() |> Base.encode64()

    """
    import assert from 'node:assert/strict'

    const timers = []
    globalThis.setTimeout = (fn) => timers.push(fn)

    const observers = []
    globalThis.MutationObserver = class {
      constructor(fn) { this.fn = fn; observers.push(this) }
      observe(node, options) { this.node = node; this.options = options }
      disconnect() { this.stopped = true }
    }

    const {default: SecretReveal} = await import('data:text/javascript;base64,#{source}')

    const classList = () => {
      const names = new Set(['grid'])
      return {
        toggle(name, on) { on ? names.add(name) : names.delete(name) },
        contains: name => names.has(name),
      }
    }

    const input = {
      id: 'api-key',
      attrs: {type: 'password'},
      selectionStart: 2,
      selectionEnd: 5,
      range: null,
      getAttribute(name) { return name in this.attrs ? this.attrs[name] : null },
      setSelectionRange(start, end) { this.range = [start, end] },
    }

    const showGlyph = {classList: classList()}
    const hideGlyph = {classList: classList()}

    const listeners = {}
    const el = {
      id: 'api-key-reveal',
      attrs: {'aria-controls': 'api-key'},
      dataset: {
        showLabel: 'Show secret, currently hidden',
        hideLabel: 'Hide secret, currently shown',
        showTitle: 'Show secret',
        hideTitle: 'Hide secret',
      },
      getAttribute(name) { return name in this.attrs ? this.attrs[name] : null },
      setAttribute(name, value) { this.attrs[name] = value },
      addEventListener(type, fn) { listeners[type] = fn },
    }

    const byId = {
      'api-key': input,
      'api-key-reveal-show': showGlyph,
      'api-key-reveal-hide': hideGlyph,
    }
    globalThis.document = {
      activeElement: null,
      getElementById: id => (id in byId ? byId[id] : null),
    }

    // The click is a LiveView JS command on the markup: it lands as a write to
    // the input's `type`, which is what the hook derives everything else from.
    const setType = (value) => {
      input.attrs.type = value
      observers.forEach(o => { if (!o.stopped && o.node === input) o.fn([], o) })
    }

    const hook = {el, ...SecretReveal}
    hook.mounted()

    #{body}

    console.log('ok')
    """
  end

  defp run(script) do
    assert {"ok\n", 0} =
             System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
  end

  test "the control's name, title and glyph follow the input's type however often it flips" do
    harness("""
    assert.equal(observers[0].node, input)
    assert.deepEqual(observers[0].options, {attributeFilter: ['type']})

    // Masked is what the server rendered, and deriving on mount agrees with it.
    assert.equal(el.attrs['aria-label'], 'Show secret, currently hidden')
    assert.equal(el.attrs.title, 'Show secret')
    assert.equal(showGlyph.classList.contains('hidden'), false)
    assert.equal(hideGlyph.classList.contains('hidden'), true)

    setType('text')
    assert.equal(el.attrs['aria-label'], 'Hide secret, currently shown')
    assert.equal(el.attrs.title, 'Hide secret')
    assert.equal(showGlyph.classList.contains('hidden'), true)
    assert.equal(hideGlyph.classList.contains('hidden'), false)

    // Two clicks inside one frame: the command flips `type` twice, so the
    // record lands back on masked. Derived state reads the record rather than
    // counting flips, so it cannot be left announcing the other one.
    setType('password')
    setType('text')
    setType('password')
    assert.equal(el.attrs['aria-label'], 'Show secret, currently hidden')
    assert.equal(el.attrs.title, 'Show secret')
    assert.equal(showGlyph.classList.contains('hidden'), false)
    assert.equal(hideGlyph.classList.contains('hidden'), true)

    // A patch resets the derived attributes, which are not sticky; `type` is,
    // so re-deriving restores the rest without the server being told anything.
    setType('text')
    el.attrs['aria-label'] = 'Show secret, currently hidden'
    el.attrs.title = 'Show secret'
    hook.updated()
    assert.equal(el.attrs['aria-label'], 'Hide secret, currently shown')
    assert.equal(el.attrs.title, 'Hide secret')

    hook.destroyed()
    assert.equal(observers[0].stopped, true)
    """)
    |> run()
  end

  test "a pointer press on the control leaves the user typing where they were" do
    harness("""
    // Browsers would focus the button on mousedown and drop the caret.
    let defaultPrevented = false
    listeners.mousedown({preventDefault: () => (defaultPrevented = true)})
    assert.equal(defaultPrevented, true)

    // Focus stayed in the input, so the selection the type swap resets is put
    // back -- after the swap, which is why it is a macrotask and not a promise.
    document.activeElement = input
    listeners.click()
    assert.equal(input.range, null)
    timers.forEach(fn => fn())
    assert.deepEqual(input.range, [2, 5])

    // Focus elsewhere is the keyboard path: nothing to restore, so nothing is.
    input.range = null
    timers.length = 0
    document.activeElement = null
    listeners.click()
    timers.forEach(fn => fn())
    assert.equal(input.range, null)
    """)
    |> run()
  end
end
