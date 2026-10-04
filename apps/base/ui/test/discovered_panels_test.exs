defmodule Bilimbi.Base.UI.DiscoveredPanelsTest do
  @moduledoc """
  What a page gets for a key nobody provides: a visible notice in a record
  page, and nothing at all in the shell's optional slot.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.UI.DiscoveredPanels

  defp panel(assigns) do
    ~H"""
    <DiscoveredPanels.discovered_panel
      key="test.nobody-provides-this"
      id="probe"
      current_scope={%{}}
      optional={@optional}
    />
    """
  end

  test "a missing panel says it is not installed" do
    html = render_component(&panel/1, %{optional: false})

    assert html =~ ~s(id="probe")
    assert html =~ "not installed (test.nobody-provides-this)"
  end

  test "a missing optional panel renders nothing" do
    assert render_component(&panel/1, %{optional: true}) |> String.trim() == ""
  end

  test "a shell key maps to one component id for the shell and its provider" do
    assert DiscoveredPanels.shell_id("shell.notifications") == "app-shell-notifications"
  end
end
