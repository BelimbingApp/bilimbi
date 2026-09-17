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

  @live_view Path.expand(
               "../../../../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js",
               __DIR__
             )

  test "a re-render while the field is revealed and focused leaves the caret where it was" do
    # The hook restores the caret for the click only. The other type swap is a
    # patch, and LiveView restores that one itself -- so this field's usability
    # rests on LiveView internals we do not own. This drives the real shipped
    # bundle, so a LiveView upgrade that changes any of them fails here instead
    # of silently appending the characters someone types mid-secret.
    #
    # It calls the four real functions the patch calls, in the order
    # `dom_patch.ts` calls them. What it does NOT prove is that a patch still
    # reaches them: that the focused-input branch is chosen for this input, and
    # that the capture, merge, sticky reapply and restore keep this order.
    # Those are `dom_patch.ts`'s to change, and only a browser would catch it.
    script = """
    import assert from 'node:assert/strict'
    import fs from 'node:fs'

    globalThis.window = {addEventListener() {}, location: {}, history: {}}
    globalThis.HTMLSelectElement = class {}
    globalThis.document = {addEventListener() {}, createElement: () => ({}), documentElement: {}}

    const bundle = fs.readFileSync('#{@live_view}', 'utf8')
    let DOM, JS
    try {
      ({DOM, JS} = await import(
        'data:text/javascript;base64,' +
          Buffer.from(bundle + '\\nexport {DOM, JS};').toString('base64')
      ))
    } catch (err) {
      assert.fail(
        'phoenix_live_view.esm.js no longer exposes DOM and JS as module bindings, so ' +
          'this pin cannot reach them. Rewrite it against the new bundle rather than ' +
          'deleting it: ' + err.message
      )
    }

    // A text input, with the one browser behaviour the whole feature rests on:
    // changing `type` drops the selection.
    const field = (attrs) => ({
      _attrs: {...attrs},
      selectionStart: 0,
      selectionEnd: 0,
      readOnly: false,
      get attributes() { return Object.keys(this._attrs).map(name => ({name})) },
      get type() { return this._attrs.type },
      get value() { return this._attrs.value },
      hasAttribute(name) { return name in this._attrs },
      getAttribute(name) { return name in this._attrs ? this._attrs[name] : null },
      removeAttribute(name) { delete this._attrs[name] },
      setAttribute(name, value) {
        const before = this._attrs[name]
        this._attrs[name] = String(value)
        if (name === 'type' && before !== this._attrs[name]) {
          this.selectionStart = this.selectionEnd = String(this._attrs.value || '').length
        }
      },
      setSelectionRange(start, end) { this.selectionStart = start; this.selectionEnd = end },
      matches: () => true,
      focus() {},
    })

    const live = field({type: 'password', name: 'api_key', value: 'sk-sample-0000'})
    // Every server render still emits the masked type; `type` is the record and
    // it is sticky, so the live DOM is what diverges.
    const rendered = field({type: 'password', name: 'api_key', value: 'sk-sample-0000'})

    // Reveal, through the real command the button's phx-click carries.
    JS.toggleAttr(live, 'type', 'text', 'password')
    assert.equal(live.getAttribute('type'), 'text')

    // The person clicks between "sk-" and "sample", then types one character.
    live.setSelectionRange(3, 3)

    // dom_patch.ts:167 -- the caret is captured before the morph, and only
    // because `hasSelectionRange` keys off the live type rather than the
    // server's.
    const {selectionStart, selectionEnd} = DOM.hasSelectionRange(live) ? live : {}
    assert.deepEqual([selectionStart, selectionEnd], [3, 3])

    // dom_patch.ts:474 -- the focused-input branch writes the server's type...
    DOM.mergeFocusedInput(live, rendered)
    assert.equal(live.getAttribute('type'), 'password')

    // ...which really does drop the caret. Without this the rest is vacuous.
    assert.notDeepEqual([live.selectionStart, live.selectionEnd], [3, 3])

    // dom_patch.ts:477 -- and the sticky record wins it back.
    DOM.applyStickyOperations(live)
    assert.equal(live.getAttribute('type'), 'text')

    // dom_patch.ts:597 -- after the morph, the captured caret goes back.
    DOM.restoreFocus(live, selectionStart, selectionEnd)
    assert.deepEqual([live.selectionStart, live.selectionEnd], [3, 3])

    console.log('ok')
    """

    run(script)
  end
end
