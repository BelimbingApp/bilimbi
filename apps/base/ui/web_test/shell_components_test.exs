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

  test "ordinary context has no warning; operator and impersonation warnings remain outside account disclosure" do
    ordinary =
      render_component(&ShellComponents.scope_warning/1, id: "warning", current_scope: scope())
      |> LazyHTML.from_fragment()

    assert Enum.empty?(LazyHTML.query(ordinary, "#warning"))
    operator = scope(%{scope: %{tenant: %{name: "Operator", id: 7, is_platform_operator: true}}})

    html =
      render_component(&ShellComponents.scope_warning/1, id: "warning", current_scope: operator)
      |> LazyHTML.from_fragment()

    assert [_] = LazyHTML.query(html, "#warning[role='note']:not([hidden])") |> Enum.to_list()
    assert LazyHTML.text(html) =~ "Platform-operator access"
    impersonated = scope(%{impersonator: %{id: 12, name: "Operator"}})

    html =
      render_component(&ShellComponents.scope_warning/1,
        id: "warning",
        current_scope: impersonated
      )
      |> LazyHTML.from_fragment()

    assert [_] =
             LazyHTML.query(html, "#warning #app-impersonation-stop[data-method='post']")
             |> Enum.to_list()

    assert LazyHTML.text(html) =~ "Viewing as Ada Lovelace"
  end
end
