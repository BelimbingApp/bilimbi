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
  under two host locales, the same harness `app_shell_js_test.exs` uses,
  because `LiveViewTest` cannot execute a hook.
  """

  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/date_time.js", __DIR__)

  # One instant inside northern-hemisphere DST and one outside it, so a zone
  # that changes offset is rendered in both of its periods.
  @instants [~U[2026-01-01 16:30:00Z], ~U[2026-07-24 07:00:00Z]]
  @formats [:datetime, :date, :time]
  @zones ["UTC", "Asia/Kuala_Lumpur", "America/New_York"]

  defp client_rendering(env) do
    cases =
      for zone <- @zones, instant <- @instants, format <- @formats do
        %{zone: zone, instant: DateTime.to_iso8601(instant), format: to_string(format)}
      end

    encoded_source = @hook |> File.read!() |> Base.encode64()
    encoded_cases = cases |> Jason.encode!() |> Base.encode64()

    script = """
    const {formatLocal} = await import("data:text/javascript;base64,#{encoded_source}")
    const cases = JSON.parse(Buffer.from("#{encoded_cases}", "base64").toString())

    console.log(JSON.stringify(cases.map(entry => ({
      ...entry,
      text: formatLocal(new Date(entry.instant), entry.zone, entry.format),
    }))))
    """

    {output, 0} = System.cmd("node", ["--input-type=module", "--eval", script], env: env)

    Map.new(Jason.decode!(output), fn %{"zone" => zone, "instant" => instant} = entry ->
      {{zone, instant, entry["format"]}, entry["text"]}
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

    test "follows a zone through its own daylight change", %{gb: gb} do
      # Same zone, two offsets: the instant decides which one is written.
      assert gb[{"America/New_York", "2026-01-01T16:30:00Z", "datetime"}] ==
               "01/01/2026, 11:30 GMT-5"

      assert gb[{"America/New_York", "2026-07-24T07:00:00Z", "datetime"}] ==
               "24/07/2026, 03:00 GMT-4"
    end
  end
end
