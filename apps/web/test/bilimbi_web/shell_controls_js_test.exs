defmodule BilimbiWeb.ShellControlsJsTest do
  use ExUnit.Case, async: true

  @controls Path.expand("../../assets/js/shell_controls.js", __DIR__)

  test "display writes reject duplicates, preserve a failed choice and allow recovery" do
    source = @controls |> File.read!() |> Base.encode64()

    script = """
    import assert from 'node:assert/strict'
    const {default: ShellControls} = await import('data:text/javascript;base64,#{source}')
    let focused = null
    const buttons = ['light', 'dark', 'system'].map(value => ({
      dataset: {preferenceKind: 'theme', preferenceValue: value},
      setAttribute(name, value) { this[name] = value },
      focus() { focused = this },
    }))
    const feedback = {hidden: true, classList: {toggle() {}}}
    const root = {
      dataset: {themeChoice: 'light'},
      querySelectorAll(selector) { return selector === '[data-preference-kind]' ? buttons : [] },
      querySelector() { return feedback },
    }
    globalThis.document = {documentElement: {dataset: {}}, addEventListener() {}, removeEventListener() {}}
    globalThis.window = {addEventListener() {}, removeEventListener() {}}
    const calls = []
    const hook = {el: root, pushEvent(event, params, callback) { calls.push({event, params, callback}) }}
    const controls = new ShellControls(hook)
    controls.save('theme', 'dark', buttons[1])
    controls.save('theme', 'system', buttons[2])
    assert.equal(calls.length, 1)
    assert.ok(buttons.every(button => button.disabled))
    assert.match(feedback.textContent, /Saving/)
    calls[0].callback({ok: false})
    assert.equal(document.documentElement.dataset.theme, 'light')
    assert.match(feedback.textContent, /Could not save/)
    assert.ok(buttons.every(button => !button.disabled))
    assert.equal(focused, buttons[1])
    controls.save('theme', 'dark', buttons[1])
    root.dataset.themeChoice = 'dark'
    calls[1].callback({ok: true})
    assert.equal(document.documentElement.dataset.theme, 'dark')
    assert.match(feedback.textContent, /Theme saved/)
    root.dataset.themeChoice = 'system'
    controls.save('theme', 'system', buttons[2])
    calls[2].callback({ok: true})
    assert.equal(document.documentElement.dataset.theme, undefined)
    assert.equal(focused, buttons[2])
    controls.connection(false)
    controls.save('theme', 'light')
    assert.equal(calls.length, 3)
    controls.connection(true)
    controls.save('theme', 'light')
    controls.connection(false)
    assert.match(feedback.textContent, /could not be confirmed/)
    controls.destroy()
    console.log('ok')
    """

    assert {"ok\n", 0} =
             System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
  end

  test "an open panel and its confirmation survive a server patch, and focus returns to the trigger" do
    source = @controls |> File.read!() |> Base.encode64()

    script = """
    import assert from 'node:assert/strict'
    const {default: ShellControls} = await import('data:text/javascript;base64,#{source}')
    let focused = null
    const option = {dataset: {preferenceKind: 'timezone', preferenceValue: 'utc'}, focus() { focused = this }}
    const trigger = {
      id: 'app-display-timezone',
      getAttribute: name => name === 'aria-controls' ? 'app-display-timezone-panel' : null,
      setAttribute(name, value) { this[name] = value },
      focus() { focused = this },
    }
    const panel = {
      id: 'app-display-timezone-panel',
      hidden: true,
      contains: node => node === option,
      querySelector: () => option,
    }
    const feedback = {hidden: true, textContent: '', classList: {toggle() {}}}
    const root = {
      dataset: {themeChoice: 'light'},
      querySelectorAll(selector) {
        if (selector === '[data-account-panel], [data-timezone-panel]') return [panel]
        if (selector === '[data-preference-kind]') return [option]
        return []
      },
      querySelector(selector) {
        return selector === '[aria-controls="app-display-timezone-panel"]' ? trigger : feedback
      },
    }
    globalThis.document = {
      documentElement: {dataset: {}},
      getElementById: id => id === panel.id ? panel : null,
      addEventListener() {}, removeEventListener() {},
    }
    globalThis.window = {addEventListener() {}, removeEventListener() {}}
    const calls = []
    const controls = new ShellControls({el: root, pushEvent(e, params, callback) { calls.push(callback) }})

    controls.toggle(trigger)
    assert.equal(panel.hidden, false)
    assert.equal(trigger['aria-expanded'], 'true')
    assert.equal(focused, option)

    // A server patch re-renders the static markup: panel hidden, trigger collapsed.
    panel.hidden = true
    trigger['aria-expanded'] = 'false'
    controls.apply()
    assert.equal(panel.hidden, false)
    assert.equal(trigger['aria-expanded'], 'true')

    controls.save('timezone', 'utc', option)
    assert.equal(option.disabled, true)
    calls[0]({ok: true})
    assert.equal(panel.hidden, true)
    assert.equal(trigger['aria-expanded'], 'false')
    assert.equal(feedback.hidden, false)
    assert.equal(feedback.textContent, 'Time display saved.')
    assert.equal(option.disabled, false)
    assert.equal(focused, trigger)

    // The same patch blanks the live region; the confirmation is restored.
    feedback.hidden = true
    feedback.textContent = ''
    controls.apply()
    assert.equal(feedback.hidden, false)
    assert.equal(feedback.textContent, 'Time display saved.')
    controls.destroy()
    console.log('ok')
    """

    assert {"ok\n", 0} =
             System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
  end

  test "a theme save outside any panel keeps focus on the operated control" do
    source = @controls |> File.read!() |> Base.encode64()

    script = """
    import assert from 'node:assert/strict'
    const {default: ShellControls} = await import('data:text/javascript;base64,#{source}')
    let focused = null
    const accountLink = {focus() { focused = this }}
    const accountTrigger = {
      id: 'app-user-toggle',
      getAttribute: name => name === 'aria-controls' ? 'app-user-panel' : null,
      setAttribute(name, value) { this[name] = value },
      focus() { focused = this },
    }
    const accountPanel = {
      id: 'app-user-panel',
      hidden: true,
      contains: node => node === accountLink,
      querySelector: () => accountLink,
    }
    const themeButton = {dataset: {preferenceKind: 'theme', preferenceValue: 'dark'}, focus() { focused = this }}
    const feedback = {hidden: true, textContent: '', classList: {toggle() {}}}
    const root = {
      dataset: {themeChoice: 'light'},
      querySelectorAll(selector) {
        if (selector === '[data-account-panel], [data-timezone-panel]') return [accountPanel]
        if (selector === '[data-preference-kind]') return [themeButton]
        return []
      },
      querySelector(selector) {
        return selector === '[aria-controls="app-user-panel"]' ? accountTrigger : feedback
      },
    }
    globalThis.document = {
      documentElement: {dataset: {}},
      getElementById: id => id === accountPanel.id ? accountPanel : null,
      addEventListener() {}, removeEventListener() {},
    }
    globalThis.window = {addEventListener() {}, removeEventListener() {}}
    const calls = []
    const controls = new ShellControls({el: root, pushEvent(e, params, callback) { calls.push(callback) }})

    controls.toggle(accountTrigger)
    assert.equal(focused, accountLink)

    // The theme control sits outside the open account panel.
    controls.save('theme', 'dark', themeButton)
    calls[0]({ok: true})
    assert.equal(accountPanel.hidden, true)
    assert.equal(focused, themeButton)
    controls.destroy()
    console.log('ok')
    """

    assert {"ok\n", 0} =
             System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
  end
end
