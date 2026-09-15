defmodule BilimbiWeb.DateTimeJsTest do
  @moduledoc """
  The client half of the `<.datetime>` display contract.

  `LiveViewTest` cannot execute a hook, so the hook's formatter is imported
  into Node and its output compared against what `<.datetime>` renders on the
  server for the same instant — the same harness `app_shell_js_test.exs` uses.

  Two regressions are pinned here, both of which shipped once:

    * a browser locale reordering the date, turning 24/07/2026 into 07/24/2026
    * the zone label appearing only for `:datetime`, not `:date` and `:time`

  `:company` and `:utc` are not covered by a formatter comparison because the
  client never formats them — it copies the server's own string. That is
  asserted in `Bilimbi.Base.UI.ComponentsDatetimeTest` and exercised end to
  end in `Bilimbi.Base.Audit.Web.MutationsDisplayModeTest`.

  ## This reverses a deliberate earlier choice

  `3dde87f` ("Refine GeoNames update UI consistency") moved this hook from
  `Intl.DateTimeFormat("en-GB", …)` with `hourCycle: "h23"` to
  `Intl.DateTimeFormat(undefined, …)`, and replaced this file with a test
  asserting exactly that — "uses the operator's browser locale and hour
  cycle". The intent was reasonable on its own terms: in `:local` mode, show
  an instant the way the reader's own device would.

  It is reversed here because it cannot hold alongside the rest of the
  product. The server writes `24/07/2026` in every mode, so a US-locale
  browser put `07/24/2026` in the same table as `24/07/2026` and, after a
  clock change, in place of it — the same digits in a different order, which
  reads as a different date rather than as a different format. One product
  convention, applied on both sides, is the only version of this that cannot
  mislead. The old assertions are not restated below; these replace them.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.UI.Components

  @hook Path.expand("../../assets/js/date_time.js", __DIR__)

  # One instant inside northern-hemisphere DST and one outside it, so a zone
  # that changes offset is compared in both of its periods.
  @instants [~U[2026-01-01 16:30:00Z], ~U[2026-07-24 07:00:00Z]]
  @formats [:datetime, :date, :time]

  # Zones whose IANA abbreviation is the numeric offset. Client and server must
  # agree on these exactly.
  @numeric_zones ["UTC", "Asia/Kuala_Lumpur", "Asia/Kathmandu"]

  # Zones whose IANA abbreviation is a letter code. The server renders the
  # letters; `:local` deliberately renders the offset instead, because the only
  # way for a browser to produce "EST" is a localized name that reads "GMT-5"
  # to a non-US browser — two users in one zone would disagree with each other.
  @letter_zones ["Europe/Paris", "America/New_York", "Australia/Adelaide"]

  defp client_rendering(env \\ []) do
    cases =
      for zone <- @numeric_zones ++ @letter_zones,
          instant <- @instants,
          format <- @formats do
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

  # What `<.datetime>` writes into `data-text-company` for that zone: the
  # server's own formatter, reached through the public component.
  defp server_rendering(zone, instant, format) do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <Components.datetime
            id="ts"
            value={@value}
            format={@format}
            display={@display}
          />
          """
        end,
        %{
          value: instant,
          format: format,
          display: %{
            mode: :company,
            timezone: zone,
            tz_db: Bilimbi.Base.DateTime.time_zone_database()
          }
        }
      )

    [_whole, text] = Regex.run(~r/data-text-company="([^"]+)"/, html)
    text
  end

  describe "the pinned client formatter" do
    setup do
      {:ok, client: client_rendering()}
    end

    test "matches the server exactly for every numeric-abbreviation zone", %{client: client} do
      for zone <- @numeric_zones, instant <- @instants, format <- @formats do
        expected = server_rendering(zone, instant, format)
        actual = client[{zone, DateTime.to_iso8601(instant), to_string(format)}]

        assert actual == expected,
               "#{zone} #{DateTime.to_iso8601(instant)} #{format}: " <>
                 "client #{inspect(actual)} != server #{inspect(expected)}"
      end
    end

    test "writes the date in the server's order, never the browser's", %{client: client} do
      # The regression: a US-locale browser rendered 24/07/2026 as 07/24/2026.
      assert client[{"UTC", "2026-07-24T07:00:00Z", "datetime"}] == "24/07/2026, 07:00 UTC"
      assert client[{"UTC", "2026-07-24T07:00:00Z", "date"}] == "24/07/2026 UTC"
    end

    test "labels the zone in all three formats, not only datetime", %{client: client} do
      # The regression: :date and :time lost the label the server always writes.
      assert client[{"Asia/Kuala_Lumpur", "2026-07-24T07:00:00Z", "datetime"}] ==
               "24/07/2026, 15:00 +08"

      assert client[{"Asia/Kuala_Lumpur", "2026-07-24T07:00:00Z", "date"}] == "24/07/2026 +08"
      assert client[{"Asia/Kuala_Lumpur", "2026-07-24T07:00:00Z", "time"}] == "15:00 +08"
    end

    test "renders a half-hour and a quarter-hour offset in the IANA shape", %{client: client} do
      assert client[{"Asia/Kathmandu", "2026-01-01T16:30:00Z", "datetime"}] ==
               "01/01/2026, 22:15 +0545"

      assert client[{"Australia/Adelaide", "2026-01-01T16:30:00Z", "datetime"}] ==
               "02/01/2026, 03:00 +1030"
    end

    test "renders a letter-abbreviation zone as its offset, deliberately", %{client: client} do
      # Pinned so the intended divergence is asserted rather than discovered.
      # The server renders CET/EST for these; `:local` renders the offset,
      # because the letters are only reachable through a localized name.
      assert client[{"Europe/Paris", "2026-01-01T16:30:00Z", "datetime"}] ==
               "01/01/2026, 17:30 +01"

      assert client[{"America/New_York", "2026-01-01T16:30:00Z", "datetime"}] ==
               "01/01/2026, 11:30 -05"

      assert server_rendering("Europe/Paris", ~U[2026-01-01 16:30:00Z], :datetime) ==
               "01/01/2026, 17:30 CET"
    end
  end

  test "a US-locale host renders identically to a UK-locale one" do
    # The root cause of the transposition was an unpinned locale, so the
    # formatter is run under a host locale and zone that would have exposed it.
    us = client_rendering([{"LC_ALL", "en_US.UTF-8"}, {"TZ", "America/New_York"}])
    gb = client_rendering([{"LC_ALL", "en_GB.UTF-8"}, {"TZ", "Europe/London"}])

    assert us == gb
    assert us[{"UTC", "2026-07-24T07:00:00Z", "datetime"}] == "24/07/2026, 07:00 UTC"
  end
end
