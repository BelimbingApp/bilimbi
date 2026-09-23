defmodule Bilimbi.Base.UI.ShellComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias Bilimbi.Base.UI.ShellComponents

  defp scope(overrides \\ %{}) do
    Map.merge(
      %{
        user: %{
          "name" => "Ada Lovelace",
          "email" => "ada@example.com",
          "company_name" => "Analytical Engines"
        },
        scope: %{tenant: %{name: "Research", id: 41, is_platform_operator: false}},
        impersonator: nil
      },
      overrides
    )
  end

  defp operator_scope(overrides \\ %{}) do
    scope(
      Map.merge(
        %{scope: %{tenant: %{name: "Operator", id: 7, is_platform_operator: true}}},
        overrides
      )
    )
  end

  defp render_warning(current_scope) do
    render_component(&ShellComponents.scope_warning/1,
      id: "warning",
      current_scope: current_scope
    )
    |> LazyHTML.from_fragment()
  end

  defp render_account_menu(current_scope) do
    render_component(&ShellComponents.account_menu/1, id: "account", current_scope: current_scope)
    |> LazyHTML.from_fragment()
  end

  test "ordinary context and platform-operator context render no strip" do
    assert Enum.empty?(LazyHTML.query(render_warning(scope()), "#warning"))

    operator = render_warning(operator_scope())
    assert Enum.empty?(LazyHTML.query(operator, "#warning"))
    refute LazyHTML.text(operator) =~ "Platform"
  end

  test "impersonation keeps the strip with its stop link, for an operator too" do
    for current_scope <- [
          scope(%{impersonator: %{id: 12, name: "Operator"}}),
          operator_scope(%{impersonator: %{id: 12, name: "Operator"}})
        ] do
      html = render_warning(current_scope)

      assert [_] = LazyHTML.query(html, "#warning[role='note']:not([hidden])") |> Enum.to_list()

      assert [_] =
               LazyHTML.query(
                 html,
                 "#warning #app-impersonation-stop[data-method='post'][href='/admin/impersonate/leave']"
               )
               |> Enum.to_list()

      assert LazyHTML.text(html) =~ "Viewing as Ada Lovelace"
      assert LazyHTML.text(html) =~ "Stop"
      refute LazyHTML.text(html) =~ "Platform"
    end
  end

  test "the account menu marks a platform-operator scope with the strip's caution tokens" do
    html = render_account_menu(operator_scope())

    assert [marker] =
             LazyHTML.query(
               html,
               "#account-panel dl #account-platform-operator.bg-warning-surface.text-warning-ink.border-warning-line"
             )
             |> Enum.to_list()

    assert LazyHTML.text(marker) =~ "Platform-operator"
    refute LazyHTML.text(marker) =~ "Owner"
    assert [_] = LazyHTML.query(html, "#account-platform-operator dd") |> Enum.to_list()
  end

  test "the account menu carries no Platform-operator marker for an ordinary scope" do
    html = render_account_menu(scope())

    assert Enum.empty?(LazyHTML.query(html, "#account-platform-operator"))
    refute LazyHTML.text(html) =~ "Platform-operator"
    assert LazyHTML.text(html) =~ "Tenant"
    assert LazyHTML.text(html) =~ "Research"
  end
end
