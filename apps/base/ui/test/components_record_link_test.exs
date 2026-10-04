defmodule Bilimbi.Base.UI.ComponentsRecordLinkTest do
  @moduledoc """
  `<.record_link>`: a row's link to its record, or the selection button of
  a page in a workspace where another tile follows that kind of record.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  use Bilimbi.Base.UI.Components

  defp row(assigns) do
    ~H"""
    <.record_link
      id="company-42"
      workspace={@workspace}
      kind="core/company"
      record_id={42}
      navigate="/companies/42"
      class="font-medium"
    >
      Bilimbi Industries
    </.record_link>
    """
  end

  test "alone it is a navigation" do
    html = render_component(&row/1, %{workspace: nil})

    assert html =~ ~s(href="/companies/42" data-phx-link="redirect")
    assert html =~ ~s(id="company-42")
    assert html =~ "Bilimbi Industries"
    refute html =~ "workspace:select"
  end

  test "in a workspace it selects, carrying the kind, the id and the page" do
    html = render_component(&row/1, %{workspace: %{token: "t", topic: "x", follows: []}})

    assert html =~ ~s(type="button" phx-click="workspace:select")
    assert html =~ ~s(phx-value-kind="core/company")
    assert html =~ ~s(phx-value-id="42")
    assert html =~ ~s(phx-value-path="/companies/42")
    assert html =~ ~s(data-record-select)
    assert html =~ ~s(id="company-42")
    assert html =~ "font-medium"
    refute html =~ "href="
  end
end
