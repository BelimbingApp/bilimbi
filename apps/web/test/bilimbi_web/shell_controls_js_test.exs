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

  test "a confirmed time display save closes the panel, confirms and returns focus to the trigger" do
    source = @controls |> File.read!() |> Base.encode64()

    script = """
    import assert from 'node:assert/strict'
    const {default: ShellControls} = await import('data:text/javascript;base64,#{source}')
    let focused = null
    const trigger = {
      id: 'app-display-timezone',
      focus() { focused = this },
      setAttribute(name, value) { this[name] = value },
    }
    const panel = {id: 'app-display-timezone-panel', hidden: false}
    const option = {dataset: {preferenceKind: 'timezone', preferenceValue: 'utc'}, focus() { focused = this }}
    const feedback = {hidden: true, classList: {toggle() {}}}
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
    globalThis.document = {documentElement: {dataset: {}}, addEventListener() {}, removeEventListener() {}}
    globalThis.window = {addEventListener() {}, removeEventListener() {}}
    const calls = []
    const controls = new ShellControls({el: root, pushEvent(e, params, callback) { calls.push(callback) }})
    controls.save('timezone', 'utc', option)
    assert.equal(option.disabled, true)
    calls[0]({ok: true})
    assert.equal(panel.hidden, true)
    assert.equal(trigger['aria-expanded'], 'false')
    assert.equal(feedback.hidden, false)
    assert.equal(feedback.textContent, 'Time display saved.')
    assert.equal(option.disabled, false)
    assert.equal(focused, trigger)
    controls.destroy()
    console.log('ok')
    """

    assert {"ok\n", 0} =
             System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
  end
end
