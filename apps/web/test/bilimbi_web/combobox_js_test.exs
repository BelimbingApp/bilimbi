defmodule BilimbiWeb.ComboboxJsTest do
  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/combobox.js", __DIR__)

  defp harness(body) do
    source = @hook |> File.read!() |> Base.encode64()

    """
    import assert from 'node:assert/strict'

    const byId = {}
    const camel = name => name.replace(/-([a-z])/g, (_, c) => c.toUpperCase())

    // Just enough DOM for the hook: attributes, `hidden`, a parent chain, and
    // events that bubble to the document unless a listener stops them.
    class Node {
      constructor(attrs = {}, children = []) {
        this.attrs = {}
        this.dataset = {}
        this.hidden = false
        this.value = ''
        this.children = []
        this.parent = null
        this.listeners = {}
        this.classes = new Set()
        this.classList = {toggle: (c, on) => (on ? this.classes.add(c) : this.classes.delete(c))}
        for (const [k, v] of Object.entries(attrs)) {
          if (k === 'hidden') this.hidden = true
          else if (k === 'value') this.value = v
          else if (k.startsWith('data-')) this.dataset[camel(k.slice(5))] = v
          else this.attrs[k] = v
        }
        this.id = attrs.id
        if (this.id) byId[this.id] = this
        children.forEach(child => { child.parent = this; this.children.push(child) })
      }
      getAttribute(name) { return name in this.attrs ? this.attrs[name] : null }
      setAttribute(name, value) { this.attrs[name] = String(value) }
      removeAttribute(name) { delete this.attrs[name] }
      addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn) }
      removeEventListener(type, fn) { this.listeners[type] = (this.listeners[type] || []).filter(f => f !== fn) }
      contains(node) { for (let n = node; n; n = n.parent) if (n === this) return true; return false }
      descendants() { return this.children.flatMap(child => [child, ...child.descendants()]) }
      querySelectorAll(selector) {
        const [, attr, suffix, expected] = selector.match(/^\\[([\\w-]+)(\\$?)="(.*)"\\]$/)
        return this.descendants().filter(node => {
          const actual = attr === 'id' ? node.id : node.getAttribute(attr)
          return actual != null && (suffix ? actual.endsWith(expected) : actual === expected)
        })
      }
      querySelector(selector) { return this.querySelectorAll(selector)[0] || null }
      select() { this.selectionStart = 0; this.selectionEnd = this.value.length }
      focus() {}
      scrollIntoView() {}
      dispatchEvent(source) {
        const event = {
          type: source.type,
          key: source.key,
          bubbles: source.bubbles,
          target: this,
          defaultPrevented: false,
          stopped: false,
          stopPropagation() { this.stopped = true },
          preventDefault() { this.defaultPrevented = true },
        }
        for (let node = this; node; node = event.bubbles ? node.parent : null) {
          ;(node.listeners[event.type] || []).forEach(fn => fn(event))
          if (event.stopped) break
        }
        return event
      }
    }

    globalThis.document = new Node()
    document.getElementById = id => byId[id] || null

    const {default: Combobox} = await import('data:text/javascript;base64,#{source}')

    const option = (value, label) =>
      new Node({id: `jurisdiction-option-${value}`, role: 'option', 'data-value': value, 'data-label': label})

    const hidden = new Node({id: 'jurisdiction-value', name: 'jurisdiction', value: 'SG', hidden: true})
    const input = new Node({id: 'jurisdiction', role: 'combobox', 'aria-expanded': 'false', value: 'Singapore'})
    const noMatches = new Node({id: 'jurisdiction-no-matches', hidden: true})
    const listbox = new Node({id: 'jurisdiction-options', role: 'listbox', hidden: true}, [
      noMatches,
      option('MY', 'Malaysia'),
      option('SG', 'Singapore'),
      option('ID', 'Indonesia'),
    ])
    const wrapper = new Node({id: 'jurisdiction-wrapper', 'data-value-id': 'jurisdiction-value'}, [
      hidden,
      input,
      listbox,
    ])

    // The enclosing form, as LiveView's delegated phx-change hears it: every
    // input or change event that bubbles out of the form is a server push.
    const form = new Node({id: 'company-jurisdiction-form'}, [wrapper])
    form.parent = document
    const pushed = []
    const record = event => pushed.push([event.type, event.target.id, event.target.value])
    document.addEventListener('input', record)
    document.addEventListener('change', record)

    const hook = {el: wrapper, pushEvent() {}, pushEventTo() {}, ...Combobox}
    hook.mounted()

    const type = text => {
      input.value = text
      input.selectionStart = input.selectionEnd = text.length
      input.dispatchEvent({type: 'input', bubbles: true})
    }
    const press = key => input.dispatchEvent({type: 'keydown', key, bubbles: true})
    const visible = () => listbox.children.filter(n => n.getAttribute('role') === 'option' && !n.hidden).map(n => n.dataset.value)

    input.dispatchEvent({type: 'focus'})
    assert.equal(listbox.hidden, false)
    assert.equal(input.getAttribute('aria-expanded'), 'true')

    #{body}

    console.log('ok')
    """
  end

  defp run(script) do
    System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
  end

  test "typing filters without a server push, and Enter commits the only match" do
    script =
      harness("""
      // An inline editor saves on phx-change: a keystroke reaching the form
      // would save the old value and close the editor mid-word.
      type('Malay')
      input.dispatchEvent({type: 'change', bubbles: true})
      assert.deepEqual(pushed, [])
      assert.deepEqual(visible(), ['MY'])
      assert.equal(input.getAttribute('aria-activedescendant'), 'jurisdiction-option-MY')

      const enter = press('Enter')
      assert.equal(enter.defaultPrevented, true)
      assert.equal(hidden.value, 'MY')
      assert.equal(input.value, 'Malaysia')
      assert.equal(listbox.hidden, true)

      // Only the committed hidden value reaches the form.
      assert.deepEqual(pushed, [
        ['input', 'jurisdiction-value', 'MY'],
        ['change', 'jurisdiction-value', 'MY'],
      ])
      """)

    assert {"ok\n", 0} = run(script)
  end

  test "Enter with no match neither commits nor submits the form" do
    script =
      harness("""
      type('zzz')
      assert.deepEqual(visible(), [])
      assert.equal(noMatches.hidden, false)

      const enter = press('Enter')
      assert.equal(enter.defaultPrevented, true)
      assert.equal(hidden.value, 'SG')
      assert.deepEqual(pushed, [])
      """)

    assert {"ok\n", 0} = run(script)
  end

  test "a server patch while the list is open keeps it open and filtered" do
    script =
      harness("""
      type('Indo')

      // morphdom restores the server-rendered closed state.
      listbox.hidden = true
      input.setAttribute('aria-expanded', 'false')
      input.removeAttribute('aria-activedescendant')
      listbox.children.forEach(n => { if (n.getAttribute('role') === 'option') n.hidden = false })
      hook.updated()

      assert.equal(listbox.hidden, false)
      assert.equal(input.getAttribute('aria-expanded'), 'true')
      assert.deepEqual(visible(), ['ID'])
      assert.equal(input.getAttribute('aria-activedescendant'), 'jurisdiction-option-ID')
      assert.equal(press('Enter').defaultPrevented, true)
      assert.equal(hidden.value, 'ID')
      """)

    assert {"ok\n", 0} = run(script)
  end
end
