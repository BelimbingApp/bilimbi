defmodule Bilimbi.Base.UI.ComponentsRestrictedTest do
  @moduledoc """
  A field the person may not see reads "Restricted" with a lock and tells
  them what to do, naming the permission when the page knows it; in a form it
  keeps its row and submits nothing. These lock the words and the contract,
  not the styling.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  use Bilimbi.Base.UI.Components

  defp text(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp marker(assigns) do
    ~H"""
    <.restricted id="tax-id-restricted" />
    """
  end

  defp marker_with_reason(assigns) do
    ~H"""
    <.restricted id="salary-restricted" reason="Salaries are shown to payroll only." />
    """
  end

  defp field(assigns) do
    ~H"""
    <form id="payee-form">
      <.restricted_field id="payee-bank-account" label="Bank account" />
    </form>
    """
  end

  test "reads Restricted with a lock and says plainly that the person has no access" do
    html = render_component(&marker/1, %{})

    assert text(html) == "Restricted"
    assert html =~ ~s(data-restricted)
    assert html =~ "hero-lock-closed"
    refute html =~ "hero-eye"

    # No role is named: the field is restricted for a role the person holds.
    assert html =~ ~s(title="You don&#39;t have access to this field.")
    assert html =~ ~s(aria-description="You don&#39;t have access to this field.")
    refute html =~ "Ask your administrator"
  end

  test "a page's own reason replaces the default sentence" do
    html = render_component(&marker_with_reason/1, %{})

    assert html =~ ~s(title="Salaries are shown to payroll only.")
    refute html =~ "You don&#39;t have access"
  end

  test "a restricted form row keeps its label, is read-only and submits nothing" do
    html = render_component(&field/1, %{})

    assert text(html) == "Bank account Restricted"
    assert html =~ ~s(data-restricted-field)
    assert html =~ ~s(aria-readonly="true")
    assert html =~ ~s(aria-labelledby="payee-bank-account-label")
    assert html =~ ~s(title="You don&#39;t have access to this field.")
    refute html =~ "<input"
    refute html =~ "<select"
    refute html =~ "<textarea"
    refute html =~ ~s(name=")
  end
end
