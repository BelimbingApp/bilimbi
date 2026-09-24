defmodule BilimbiWeb.DateTimeJsTest do
  @moduledoc """
  The client half of the `<.datetime>` display contract.

  `:company` and `:utc` are decided by the server, and the hook copies the
  string the server wrote rather than formatting one — asserted in
  `Bilimbi.Base.UI.ComponentsDatetimeTest` and exercised end to end in
  `Bilimbi.Base.Audit.Web.MutationsDisplayModeTest`.

  `:local` is the one mode the server cannot decide, because it does not know
  the browser's zone, so the hook formats it. It formats it the way the
  reader's own device would: their locale orders the fields and chooses the
  hour cycle, which is the point of choosing this device's local time at all.
  That is what is pinned here — the formatter is imported into Node and run
  under two host locales, which the in-process hook tests in
  `apps/web/assets/test` cannot switch.
  """

  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/date_time.js", __DIR__)

  # One instant inside northern-hemisphere DST and one outside it, so a zone
  # that changes offset is rendered in both of its periods.
  @instants [~U[2026-01-01 16:30:00Z], ~U[2026-07-24 07:00:00Z]]
  @formats [:datetime, :date, :time]
  @zones ["UTC", "Asia/Kuala_Lumpur", "America/New_York"]
  @precisions [:minute, :second]

  defp client_rendering(env) do
    cases =
      for zone <- @zones, instant <- @instants, format <- @formats, precision <- @precisions do
        %{
          zone: zone,
          instant: DateTime.to_iso8601(instant),
          format: to_string(format),
          precision: to_string(precision)
        }
      end

    encoded_source = @hook |> File.read!() |> Base.encode64()
    encoded_cases = cases |> Jason.encode!() |> Base.encode64()

    script = """
    const {formatLocal} = await import("data:text/javascript;base64,#{encoded_source}")
    const cases = JSON.parse(Buffer.from("#{encoded_cases}", "base64").toString())

    console.log(JSON.stringify(cases.map(entry => ({
      ...entry,
      text: formatLocal(new Date(entry.instant), entry.zone, entry.format, entry.precision),
    }))))
    """

    {output, 0} = System.cmd("node", ["--input-type=module", "--eval", script], env: env)

    Map.new(Jason.decode!(output), fn
      %{"zone" => zone, "instant" => instant, "precision" => "minute"} = entry ->
        {{zone, instant, entry["format"]}, entry["text"]}

      %{"zone" => zone, "instant" => instant, "precision" => precision} = entry ->
        {{zone, instant, entry["format"], precision}, entry["text"]}
    end)
  end

  describe "the client formatter for :local" do
    setup do
      # A host in each of the two conventions that disagree about field order
      # and hour cycle, so following the reader is observable rather than
      # asserted against the source.
      {:ok,
       us: client_rendering([{"LC_ALL", "en_US.UTF-8"}, {"TZ", "America/New_York"}]),
       gb: client_rendering([{"LC_ALL", "en_GB.UTF-8"}, {"TZ", "Europe/London"}])}
    end

    test "orders the date the reader's own way", %{us: us, gb: gb} do
      key = {"UTC", "2026-07-24T07:00:00Z", "datetime"}

      assert gb[key] == "24/07/2026, 07:00 UTC"
      assert String.starts_with?(us[key], "07/24/2026")
      assert us != gb
    end

    test "uses the reader's own hour cycle", %{us: us, gb: gb} do
      key = {"UTC", "2026-01-01T16:30:00Z", "time"}

      assert gb[key] == "16:30"
      assert us[key] =~ "04:30"
      assert us[key] =~ "PM"
    end

    test "renders the browser's zone, not the host's clock", %{gb: gb} do
      # The instant is 07:00 UTC; a reader in Kuala Lumpur reads 15:00, on a
      # host whose own zone is London.
      assert gb[{"Asia/Kuala_Lumpur", "2026-07-24T07:00:00Z", "datetime"}] ==
               "24/07/2026, 15:00 GMT+8"
    end

    test "names the zone on a full datetime only", %{us: us, gb: gb} do
      # A datetime reads "<date>, <time> <zone>"; a bare date or time carries
      # no label, because the label qualifies the pair.
      for rendering <- [us, gb], zone <- @zones, instant <- @instants do
        key = fn format -> rendering[{zone, DateTime.to_iso8601(instant), format}] end
        date = key.("date")
        time = key.("time")

        label =
          key.("datetime")
          |> String.replace_prefix("#{date}, ", "")
          |> String.replace_prefix(time, "")
          |> String.trim()

        assert label != "", "#{zone} #{instant}: #{inspect(key.("datetime"))} names no zone"
        refute String.contains?(date, label)
        refute String.contains?(time, label)
      end
    end

    test "adds seconds only when the instant asks for them", %{gb: gb} do
      key = {"Asia/Kuala_Lumpur", "2026-07-24T07:00:00Z", "datetime"}

      assert gb[key] == "24/07/2026, 15:00 GMT+8"
      assert gb[Tuple.insert_at(key, 3, "second")] == "24/07/2026, 15:00:00 GMT+8"
      assert gb[{"UTC", "2026-01-01T16:30:00Z", "time", "second"}] == "16:30:00"
      assert gb[{"UTC", "2026-01-01T16:30:00Z", "date", "second"}] == "01/01/2026"
    end

    test "follows a zone through its own daylight change", %{gb: gb} do
      # Same zone, two offsets: the instant decides which one is written.
      assert gb[{"America/New_York", "2026-01-01T16:30:00Z", "datetime"}] ==
               "01/01/2026, 11:30 GMT-5"

      assert gb[{"America/New_York", "2026-07-24T07:00:00Z", "datetime"}] ==
               "24/07/2026, 03:00 GMT-4"
    end
  end

  describe "the shell observer's lifetime" do
    # One page-level MutationObserver repaints every mounted instant when the
    # shell publishes a new mode. It holds `#app-shell` — the root of the whole
    # page — so it must not outlive the instants that need it, and must not be
    # torn down while any of them remain.
    setup do
      {:ok, lifetime: observer_lifetime()}
    end

    test "arms one observer for the whole page, not one per instant", %{lifetime: l} do
      assert l["created"] == 1
      assert l["armedAfterMount"] == 1
    end

    test "keeps observing while any instant is still mounted", %{lifetime: l} do
      # LiveView mounts the incoming view's hooks before destroying the
      # outgoing view's, so a destroy with instances remaining is the ordinary
      # navigation case and must not disarm the survivors' observer.
      assert l["armedAfterFirstDestroy"] == 1
    end

    test "releases the detached shell once the last instant goes", %{lifetime: l} do
      # The leak this closes: without it the observer keeps a strong reference
      # to a detached #app-shell after navigating to a page with no instants,
      # retaining that whole previous page's DOM.
      assert l["armedAfterLastDestroy"] == 0
    end

    test "re-arms for a later page that does carry instants", %{lifetime: l} do
      assert l["createdAfterRemount"] == 2
      assert l["armedAfterRemount"] == 1
    end
  end

  # Drives mount/destroy against a stubbed MutationObserver and shell, and
  # reports how many observers were created and how many remain connected.
  defp observer_lifetime do
    encoded_source = @hook |> File.read!() |> Base.encode64()

    script = """
    const {default: DateTime} = await import("data:text/javascript;base64,#{encoded_source}")

    const observers = []
    globalThis.MutationObserver = class {
      constructor(callback) {
        this.callback = callback
        this.connected = false
        observers.push(this)
      }
      observe() { this.connected = true }
      disconnect() { this.connected = false }
    }

    const shell = {dataset: {displayMode: "utc"}}
    globalThis.document = {querySelector: s => (s === "#app-shell" ? shell : null)}

    const instant = () => {
      const hook = Object.create(DateTime)
      hook.el = {
        dateTime: "2026-08-18T10:00:00Z",
        dataset: {
          format: "datetime",
          mode: "utc",
          followShell: "true",
          textUtc: "18/08/2026, 10:00 UTC",
          textCompany: "18/08/2026, 18:00 +08",
        },
        textContent: "",
        title: null,
        removeAttribute() {},
      }
      return hook
    }

    const armed = () => observers.filter(o => o.connected).length

    const first = instant()
    const second = instant()
    first.mounted()
    second.mounted()
    const armedAfterMount = armed()
    const created = observers.length

    first.destroyed()
    const armedAfterFirstDestroy = armed()

    second.destroyed()
    const armedAfterLastDestroy = armed()

    instant().mounted()
    const createdAfterRemount = observers.length
    const armedAfterRemount = armed()

    console.log(JSON.stringify({
      created,
      armedAfterMount,
      armedAfterFirstDestroy,
      armedAfterLastDestroy,
      createdAfterRemount,
      armedAfterRemount,
    }))
    """

    {output, 0} = System.cmd("node", ["--input-type=module", "--eval", script])
    Jason.decode!(output)
  end
end
