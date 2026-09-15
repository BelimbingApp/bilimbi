defmodule Bilimbi.Base.UI.ComponentsDatetimeTest do
  @moduledoc """
  `<.datetime>` under the three display modes (#459).

  The component honors the per-process `DateTimeDisplay` context the web
  edge sets, or an explicit `display` attr. The server text is the complete
  answer in every mode, so the no-JavaScript fallback is the rendering
  itself.

  Every instant also carries the two modes the server can decide, so an
  instant already on screen can follow a saved mode change without the
  server re-rendering it — the case that matters is a LiveView stream, whose
  rows the server hands to the DOM and then forgets. The hook only ever
  copies one of those strings; see `date_time_js_test.exs` for the client
  side of the same contract.
  """

  use ExUnit.Case, async: false

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  alias Bilimbi.Base.UI.DateTimeDisplay

  # Base UI takes the time zone database as a value and has no dependency on
  # any real one — this stub is the proof.
  defmodule FakeDb do
    @behaviour Calendar.TimeZoneDatabase

    @impl true
    def time_zone_period_from_utc_iso_days(_iso_days, "Test/Plus8"),
      do: {:ok, %{std_offset: 0, utc_offset: 8 * 3600, zone_abbr: "+08"}}

    def time_zone_period_from_utc_iso_days(_iso_days, "Test/Cet"),
      do: {:ok, %{std_offset: 0, utc_offset: 3600, zone_abbr: "CET"}}

    def time_zone_period_from_utc_iso_days(_iso_days, _zone), do: {:error, :time_zone_not_found}

    @impl true
    def time_zone_periods_from_wall_datetime(_dt, _zone), do: {:error, :time_zone_not_found}
  end

  # The context is process state; each test starts clean.
  setup do
    DateTimeDisplay.put(nil)
    on_exit(fn -> DateTimeDisplay.put(nil) end)
    :ok
  end

  defp render_datetime(assigns_map) do
    render_component(
      fn assigns ->
        ~H"""
        <.datetime id="ts" value={@value} format={@format} display={@display} />
        """
      end,
      Map.merge(%{value: ~N[2026-01-01 16:30:00], format: :datetime, display: nil}, assigns_map)
    )
  end

  test "nil renders the em dash" do
    assert render_datetime(%{value: nil}) =~ ">—<"
  end

  test "a calendar date renders zone-free with no mode logic and no hook" do
    # A %Date{} is not an instant: converting it through company/local modes
    # could shift the day, so it renders as-is with no zone suffix (#619).
    html = render_datetime(%{value: ~D[2026-01-02], format: :date})

    assert html =~ "02/01/2026"
    refute html =~ "UTC"
    refute html =~ "phx-hook"
    assert html =~ ~s(datetime="2026-01-02")
  end

  test "a calendar date ignores an explicit display context" do
    html =
      render_datetime(%{
        value: ~D[2026-01-02],
        format: :date,
        display: %{mode: :company, timezone: "Asia/Kuala_Lumpur"}
      })

    assert html =~ "02/01/2026"
    refute html =~ "+08"
  end

  test "no context renders local mode: UTC-labelled text with the browser hook" do
    html = render_datetime(%{})
    assert html =~ "01/01/2026, 16:30 UTC"
    assert html =~ ~s(phx-hook="DateTime")
    assert html =~ ~s(datetime="2026-01-01T16:30:00Z")
  end

  test "utc mode renders final stored-UTC text" do
    DateTimeDisplay.put(%{mode: :utc})
    html = render_datetime(%{})
    assert html =~ ">\n  01/01/2026, 16:30 UTC\n<"
  end

  test "company mode shifts through the provided database and labels the zone" do
    DateTimeDisplay.put(%{
      mode: :company,
      timezone: "Test/Plus8",
      tz_db: FakeDb
    })

    html = render_datetime(%{})
    assert html =~ ">\n  02/01/2026, 00:30 +08\n<"
    # The ISO value stays the stored UTC instant, not a rewritten one.
    assert html =~ ~s(datetime="2026-01-01T16:30:00Z")
  end

  test "company mode with an unconvertible zone falls back to truthful UTC text" do
    DateTimeDisplay.put(%{
      mode: :company,
      timezone: "Atlantis/Sunken",
      tz_db: FakeDb
    })

    assert render_datetime(%{}) =~ "01/01/2026, 16:30 UTC"
  end

  test "an explicit display attr wins over the process context" do
    DateTimeDisplay.put(%{mode: :utc})

    html =
      render_datetime(%{
        display: %{mode: :company, timezone: "Test/Cet", tz_db: FakeDb}
      })

    assert html =~ "01/01/2026, 17:30 CET"
  end

  test "date and time formats honor the mode" do
    DateTimeDisplay.put(%{
      mode: :company,
      timezone: "Test/Plus8",
      tz_db: FakeDb
    })

    assert render_datetime(%{format: :date}) =~ "02/01/2026 +08"
    assert render_datetime(%{format: :time}) =~ "00:30 +08"
  end

  describe "following a saved mode change" do
    test "an instant carries both server-decided modes whatever mode is current" do
      # The browser swaps between these two strings. It never formats them, so
      # a streamed row can follow a mode change with no server round trip and
      # no chance of the two renderings disagreeing.
      DateTimeDisplay.put(%{mode: :company, timezone: "Test/Plus8", tz_db: FakeDb})

      html = render_datetime(%{})

      assert html =~ ~s(data-text-company="02/01/2026, 00:30 +08")
      assert html =~ ~s(data-text-utc="01/01/2026, 16:30 UTC")
      assert html =~ ~s(data-mode="company")
      assert html =~ ~s(phx-hook="DateTime")
    end

    test "the same two strings are carried while the current mode is utc" do
      DateTimeDisplay.put(%{mode: :utc, timezone: "Test/Plus8", tz_db: FakeDb})

      html = render_datetime(%{})

      assert html =~ ~s(data-text-company="02/01/2026, 00:30 +08")
      assert html =~ ~s(data-text-utc="01/01/2026, 16:30 UTC")
    end

    test "the same two strings are carried while the current mode is local" do
      DateTimeDisplay.put(%{mode: :local, timezone: "Test/Plus8", tz_db: FakeDb})

      html = render_datetime(%{})

      assert html =~ ~s(data-text-company="02/01/2026, 00:30 +08")
      assert html =~ ~s(data-text-utc="01/01/2026, 16:30 UTC")
      # Local keeps the truthful UTC-labelled text until the browser enhances.
      assert html =~ ">\n  01/01/2026, 16:30 UTC\n<"
    end

    test "an unconvertible company zone carries the truthful UTC text in both" do
      DateTimeDisplay.put(%{mode: :utc, timezone: "Atlantis/Sunken", tz_db: FakeDb})

      html = render_datetime(%{})

      assert html =~ ~s(data-text-company="01/01/2026, 16:30 UTC")
      assert html =~ ~s(data-text-utc="01/01/2026, 16:30 UTC")
    end

    test "an explicit display attr opts the instant out of following the shell" do
      # The caller has already decided what this instant shows, so a shell
      # mode change must not overwrite it.
      html = render_datetime(%{display: %{mode: :company, timezone: "Test/Cet", tz_db: FakeDb}})

      refute html =~ "data-follow-shell"
      assert html =~ ~s(data-mode="company")
    end

    test "an instant with no explicit display follows the shell" do
      DateTimeDisplay.put(%{mode: :utc})

      assert render_datetime(%{}) =~ ~s(data-follow-shell="true")
    end

    test "a calendar date carries no mode metadata and no hook" do
      DateTimeDisplay.put(%{mode: :company, timezone: "Test/Plus8", tz_db: FakeDb})

      html = render_datetime(%{value: ~D[2026-01-02], format: :date})

      refute html =~ "phx-hook"
      refute html =~ "data-text-company"
      refute html =~ "data-mode"
    end

    test "date and time formats carry the zone label in both server strings" do
      # The label is part of the convention in every format. The client side
      # dropped it for :date and :time once; both sides are pinned now.
      DateTimeDisplay.put(%{mode: :company, timezone: "Test/Plus8", tz_db: FakeDb})

      date = render_datetime(%{format: :date})
      assert date =~ ~s(data-text-company="02/01/2026 +08")
      assert date =~ ~s(data-text-utc="01/01/2026 UTC")

      time = render_datetime(%{format: :time})
      assert time =~ ~s(data-text-company="00:30 +08")
      assert time =~ ~s(data-text-utc="16:30 UTC")
    end
  end
end
