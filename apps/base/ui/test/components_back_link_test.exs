defmodule Bilimbi.Base.UI.ComponentsBackLinkTest do
  @moduledoc """
  The demoted "← Back" navigation every page header uses instead of a button.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  test "renders a plain navigation link reading Back, never a button" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.back_link id="address-back-list" navigate="/addresses" />
      """)

    assert html =~ ~r/<a\b[^>]*\bid="address-back-list"/
    assert html =~ ~s(href="/addresses")
    assert html =~ ~s(data-phx-link="redirect")
    assert visible_text(html) == "← Back"
    refute html =~ "<button"
    refute html =~ "bg-action"
    refute html =~ "border"
    assert html =~ "text-link"
  end

  test "names the destination through title and label while keeping the visible text" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.back_link id="address-back-company" navigate="/companies/7" title="Back to company" />
      """)

    assert html =~ ~s(title="Back to company")
    assert html =~ ~s(aria-label="Back to company")
    assert html =~ ~r/<span\b[^>]*aria-hidden="true">←<\/span>/
    assert visible_text(html) == "← Back"
  end

  defp visible_text(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
