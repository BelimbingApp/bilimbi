defmodule Bilimbi.Base.Audit.Web.MutationsDisplayModeTest do
  @moduledoc """
  Saving a new clock mode changes the times already on screen (#710 review).

  `/audit/mutations` is a LiveView stream: the server hands each row to the
  DOM once and keeps no copy of it, so re-assigning a display value does not
  re-render a row the user is looking at. This walks the whole path on the
  page whose entire purpose is to say when something happened —

    1. the row renders in company time, carrying both server-decided modes
    2. the shell control is used to save Stored UTC
    3. the shell publishes the new mode, and the streamed row is untouched
       by the server, which is exactly why the browser has to finish the job
    4. the hook, given that untouched markup and the published mode, renders
       the stored-UTC text

  Step 4 runs the real hook in Node against the real server markup, because
  `LiveViewTest` cannot execute a hook. The same harness pins the one case
  where the browser cannot finish the job: an engine that cannot format the
  reader's own zone falls back to the server's stored-UTC text rather than
  leaving the previous mode's string under a control that now reports a
  different one.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.DateTime, as: DateTimePolicy
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @hook Path.expand("../../../web/assets/js/date_time.js", __DIR__)

  # 10:00 UTC is 18:00 the same day in Asia/Kuala_Lumpur, so the two modes
  # differ in the hour and in the label, and neither can pass for the other.
  @occurred_at ~N[2026-08-18 10:00:00]
  @company_text "18/08/2026, 18:00 +08"
  @utc_text "18/08/2026, 10:00 UTC"

  setup do
    UserFixtures.create_user_tables!()
    AuditFixtures.create_audit_tables!()
    SettingsFixtures.create_settings_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    {:ok, scope} = Tenancy.scope(41)

    :ok =
      Settings.put(
        "localization.timezone",
        "Asia/Kuala_Lumpur",
        SettingsScope.company(73, 41)
      )
      |> case do
        {:ok, _value} -> :ok
        other -> other
      end

    {:ok, :company} = DateTimePolicy.put_mode(SettingsScope.user(91, 73, 41), "company")

    grant_capabilities!("admin.audit.log.list")

    {:ok, mutation} =
      Audit.record_mutation(scope, %{
        company_id: 73,
        actor_type: "user",
        actor_id: 91,
        actor_role: "owner",
        auditable_type: "Bilimbi.Core.Company",
        auditable_id: "73",
        subject_name: "Acme Corp",
        event: "updated",
        occurred_at: @occurred_at,
        old_values: %{"name" => "Acme Inc"},
        new_values: %{"name" => "Acme Corp"},
        trace_id: "trc123456"
      })

    # Granting the capability and writing the company setting are themselves
    # captured mutations, so the row under test is addressed by its own id
    # rather than by position in the stream.
    %{scope: scope, mutation_id: mutation.id}
  end

  test "saving Stored UTC changes the time in a streamed row already on screen", %{
    conn: conn,
    mutation_id: mutation_id
  } do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/mutations")

    # 1. The row is on screen in company time. This is also the no-JavaScript
    # contract: the server text is the complete answer, not a placeholder the
    # hook fills in.
    assert has_element?(view, "#app-shell[data-display-mode='company']")
    before = streamed_instant(render(view), mutation_id)
    assert before.text == @company_text

    # The row carries both server-decided modes, so the browser will never
    # have to format one of them itself.
    assert before.attributes["data-text-company"] == @company_text
    assert before.attributes["data-text-utc"] == @utc_text
    assert before.attributes["data-follow-shell"] == "true"

    # 2. Save Stored UTC through the shell control's own event.
    render_hook(view, "shell:preference", %{kind: "timezone", value: "utc"})

    # 3. The shell publishes the new mode...
    assert has_element?(view, "#app-shell[data-display-mode='utc']")
    assert {:ok, :utc} == {:ok, DateTimePolicy.mode(SettingsScope.user(91, 73, 41))}

    # ...and the streamed row is untouched. This is the defect this change
    # exists for: without the browser, the user would still be reading 18:00
    # +08 under a control that now says UTC.
    unchanged = streamed_instant(render(view), mutation_id)
    assert unchanged.text == @company_text
    assert unchanged.attributes == before.attributes

    # 4. The hook, given that same untouched markup and the published mode,
    # renders the stored-UTC text — no reload, no server round trip.
    assert client_text(unchanged.attributes, @company_text, "utc") == @utc_text

    # And back again, from the same markup.
    assert client_text(unchanged.attributes, @utc_text, "company") == @company_text
  end

  test "an instant pinned to its own display context ignores the shell mode", %{
    conn: conn,
    mutation_id: mutation_id
  } do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/mutations")
    row = streamed_instant(render(view), mutation_id)

    # A caller that passes `display` has already decided what its instant
    # shows, and the component omits `data-follow-shell` for it.
    pinned = Map.delete(row.attributes, "data-follow-shell")

    assert client_text(pinned, @company_text, "utc") == @company_text
  end

  test "a browser that cannot format the local zone reads stored UTC, not the old mode", %{
    conn: conn,
    mutation_id: mutation_id
  } do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/mutations")
    row = streamed_instant(render(view), mutation_id)

    # The reader saves this device's local time while looking at company time.
    # An engine that cannot build the formatter must not leave 18:00 +08
    # standing under a control that now says Local: the text has to be one the
    # server vouches for.
    assert client_text(row.attributes, @company_text, "local", zone_unsupported: true) ==
             @utc_text
  end

  # The `<time>` the streamed row rendered, as the browser would receive it.
  defp streamed_instant(html, mutation_id) do
    [_whole, attributes, text] =
      Regex.run(
        ~r|<time([^>]*\bid="mutation-occurred-#{mutation_id}"[^>]*)>(.*?)</time>|s,
        html
      )

    attributes =
      ~r/([\w-]+)="([^"]*)"/
      |> Regex.scan(attributes)
      |> Map.new(fn [_whole, name, value] -> {name, value} end)

    %{attributes: attributes, text: String.trim(text)}
  end

  # Runs the real hook over the real markup, with the shell publishing `mode`.
  defp client_text(attributes, server_text, mode, opts \\ []) do
    encoded_source = @hook |> File.read!() |> Base.encode64()

    payload =
      Jason.encode!(%{
        attributes: attributes,
        text: server_text,
        mode: mode
      })

    script = """
    const {default: DateTime} = await import("data:text/javascript;base64,#{encoded_source}")
    const input = JSON.parse(Buffer.from("#{Base.encode64(payload)}", "base64").toString())

    globalThis.MutationObserver = class {
      observe() {}
      disconnect() {}
    }

    #{unsupported_zone_stub(opts[:zone_unsupported])}

    const shell = {dataset: {displayMode: input.mode}}
    globalThis.document = {
      querySelector: selector => (selector === "#app-shell" ? shell : null),
    }

    // The element the server sent, with its data-* attributes as a dataset.
    const dataset = {}
    for (const [name, value] of Object.entries(input.attributes)) {
      if (!name.startsWith("data-")) continue
      const key = name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())
      dataset[key] = value
    }

    const el = {
      dateTime: input.attributes.datetime,
      dataset,
      textContent: input.text,
      title: null,
      removeAttribute(name) { if (name === "title") this.title = null },
    }

    const hook = Object.create(DateTime)
    hook.el = el
    hook.mounted()

    console.log(JSON.stringify({text: el.textContent}))
    """

    {output, 0} = System.cmd("node", ["--input-type=module", "--eval", script])
    Jason.decode!(output)["text"]
  end

  # An engine that resolves its own zone but cannot build a formatter for it,
  # the shape a browser `Intl` gap takes: an unknown zone or an option the
  # engine does not implement makes the constructor raise.
  defp unsupported_zone_stub(true) do
    """
    const resolved = Intl.DateTimeFormat
    globalThis.Intl = {
      DateTimeFormat: function (...args) {
        if (args.length === 0) return new resolved()
        throw new RangeError("Invalid time zone specified")
      },
    }
    """
  end

  defp unsupported_zone_stub(_other), do: ""
end
