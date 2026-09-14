defmodule Bilimbi.Base.UI.ComponentsDatetimeTest do
  @moduledoc """
  `<.datetime>` under the three display modes (#459).

  The component honors the per-process `DateTimeDisplay` context the web
  edge sets, or an explicit `display` attr. `:local` keeps the truthful
  UTC-labelled server text plus the browser hook; `:company` and `:utc`
  render final server text with no hook, so the no-JavaScript fallback is
  the answer itself.
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

  test "utc mode renders final stored-UTC text with no hook" do
    DateTimeDisplay.put(%{mode: :utc})
    html = render_datetime(%{})
    assert html =~ "01/01/2026, 16:30 UTC"
    refute html =~ "phx-hook"
  end

  test "company mode shifts through the provided database and labels the zone" do
    DateTimeDisplay.put(%{
      mode: :company,
      timezone: "Test/Plus8",
      tz_db: FakeDb
    })

    html = render_datetime(%{})
    assert html =~ "02/01/2026, 00:30 +08"
    refute html =~ "phx-hook"
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
end
