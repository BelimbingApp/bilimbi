defmodule BilimbiWeb.ShellControlsJsTest do
  use ExUnit.Case, async: true

  @controls Path.expand("../../assets/js/shell_controls.js", __DIR__)
  @datetime Path.expand("../../assets/js/date_time.js", __DIR__)

  test "display writes reject duplicates, preserve a failed choice and allow recovery" do
    source = @controls |> File.read!() |> Base.encode64()

    script = """
    import assert from 'node:assert/strict'
    const {default: ShellControls} = await import('data:text/javascript;base64,#{source}')
    const buttons = ['light', 'dark', 'system'].map(value => ({
      dataset: {preferenceKind: 'theme', preferenceValue: value},
      setAttribute(name, value) { this[name] = value },
    }))
    const feedback = {hidden: true, classList: {toggle() {}}}
    const root = {
      dataset: {themeChoice: 'light', displayMode: 'company', displayTimezone: 'UTC'},
      querySelectorAll(selector) { return selector === '[data-preference-kind]' ? buttons : [] },
      querySelector() { return feedback },
    }
    globalThis.document = {documentElement: {dataset: {}}, addEventListener() {}, removeEventListener() {}}
    globalThis.window = {addEventListener() {}, removeEventListener() {}, dispatchEvent() {}}
    globalThis.CustomEvent = class {}
    const calls = []
    const hook = {el: root, pushEvent(event, params, callback) { calls.push({event, params, callback}) }}
    const controls = new ShellControls(hook)
    controls.save('theme', 'dark')
    controls.save('theme', 'system')
    assert.equal(calls.length, 1)
    assert.ok(buttons.every(button => button.disabled))
    assert.match(feedback.textContent, /Saving/)
    calls[0].callback({ok: false})
    assert.equal(document.documentElement.dataset.theme, 'light')
    assert.equal(buttons[0]['aria-pressed'], 'true')
    assert.match(feedback.textContent, /Could not save/)
    assert.ok(buttons.every(button => !button.disabled))
    controls.save('theme', 'dark')
    calls[1].callback({ok: true, preferences: {theme: 'dark', mode: 'local', timezone: 'UTC'}})
    assert.equal(document.documentElement.dataset.theme, 'dark')
    assert.equal(root.dataset.displayMode, 'local')
    assert.match(feedback.textContent, /Theme saved/)
    controls.save('theme', 'system')
    calls[2].callback({ok: true, preferences: {theme: 'system', mode: 'local', timezone: 'UTC'}})
    assert.equal(document.documentElement.dataset.theme, undefined)
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

  test "existing and newly mounted timestamps follow the shell while explicit display stays independent" do
    source = @datetime |> File.read!() |> Base.encode64()

    script = """
    import assert from 'node:assert/strict'
    const {default: DateTime} = await import('data:text/javascript;base64,#{source}')
    const events = new Map()
    globalThis.window = {addEventListener(name, fn) { events.set(fn, name) }, removeEventListener(name, fn) { events.delete(fn) }}
    const shell = {dataset: {displayMode: 'utc', displayTimezone: 'Asia/Kuala_Lumpur'}}
    const timestamp = (follow = 'true') => ({
      dateTime: '2026-09-14T07:00:00Z',
      dataset: {format: 'datetime', mode: 'utc', followShell: follow},
      closest() { return shell },
    })
    const hook = {...DateTime, el: timestamp()}
    hook.mounted()
    assert.equal(hook.el.textContent, '14/09/2026, 07:00 UTC')
    shell.dataset.displayMode = 'company'
    hook.onDisplay()
    assert.equal(hook.el.dataset.timezone, 'Asia/Kuala_Lumpur')
    assert.notEqual(hook.el.textContent, '14/09/2026, 07:00 UTC')
    const newRow = {...DateTime, el: timestamp()}
    newRow.mounted()
    assert.equal(newRow.el.textContent, hook.el.textContent)
    const explicit = {...DateTime, el: timestamp('false')}
    explicit.mounted()
    assert.equal(explicit.el.textContent, '14/09/2026, 07:00 UTC')
    hook.destroyed(); newRow.destroyed(); explicit.destroyed()
    assert.equal(events.size, 0)
    console.log('ok')
    """

    assert {"ok\n", 0} =
             System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
  end
end
