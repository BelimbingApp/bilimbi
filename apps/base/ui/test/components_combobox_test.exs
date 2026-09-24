defmodule Bilimbi.Base.UI.ComponentsComboboxTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp combobox_field(assigns) do
    ~H"""
    <.combobox
      id="country"
      name="company[jurisdiction]"
      label="Jurisdiction"
      value={@value}
      placeholder="Select country..."
      options={@options}
      errors={@errors}
    />
    """
  end

  test "renders a named hidden value and an accessible filter input" do
    html =
      render_component(&combobox_field/1,
        value: "MY",
        options: [{"Malaysia (MY)", "MY"}, {"Singapore (SG)", "SG"}],
        errors: []
      )

    assert html =~
             ~s(<input type="text" hidden id="country-value" name="company[jurisdiction]" value="MY")

    assert html =~ ~s(<input id="country" type="text" role="combobox")
    assert html =~ ~s(aria-controls="country-options")
    assert html =~ ~s(aria-expanded="false")
    assert html =~ "value=\"Malaysia (MY)\""
    assert html =~ ~s(id="country-options" role="listbox")

    assert html =~
             ~s|id="country-option-MY" role="option" data-value="MY" data-label="Malaysia (MY)" aria-selected="true"|

    assert html =~ ~s|data-label="Singapore (SG)"|

    assert html =~
             ~s|id="country-option-SG" role="option" data-value="SG" data-label="Singapore (SG)" aria-selected="false"|

    refute html =~ ~s(<select)
  end

  test "renders empty and validation states in the listbox field" do
    html =
      render_component(&combobox_field/1,
        value: nil,
        options: [],
        errors: ["Choose a country before continuing."]
      )

    assert html =~ "No options available."
    assert html =~ ~s(id="country-no-matches")
    assert html =~ "Choose a country before continuing."
    assert html =~ ~s(aria-invalid="true")
    assert html =~ ~s(phx-hook="Combobox")
  end

  test "a form field supplies the committed value and name" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <.combobox
            field={@form[:jurisdiction]}
            label="Jurisdiction"
            options={[{"Malaysia (MY)", "MY"}, {"Singapore (SG)", "SG"}]}
          />
          """
        end,
        %{form: to_form(%{"jurisdiction" => "SG"}, as: :company)}
      )

    assert html =~ ~s(name="company[jurisdiction]" value="SG")
    assert html =~ ~s|value="Singapore (SG)"|
  end
end
