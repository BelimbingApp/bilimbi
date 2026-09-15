defmodule Bilimbi.Base.UI.ComponentsRadioGroupTest do
  @moduledoc """
  Tests for the shared `<.radio_group>`: a selected choice among visible
  options, disabled and focus states, and form-field wiring.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp group(assigns) do
    ~H"""
    <.radio_group
      id="appearance"
      name="sample[radio_field]"
      label="Appearance"
      value={@value}
      disabled={@disabled}
      options={[{"System", "system"}, {"Light", "light"}, {"Dark", "dark"}]}
    />
    """
  end

  test "renders a labelled group with the selected option checked" do
    html = render_component(&group/1, %{value: "system", disabled: false})

    assert html =~ ~s(id="appearance")
    assert html =~ "Appearance"
    assert html =~ ~s(name="sample[radio_field]")
    assert html =~ ~s(id="appearance-system")
    assert html =~ ~s(value="system")
    assert html =~ ~s(value="light")
    assert html =~ ~s(value="dark")
    assert html =~ "checked"
    assert html =~ "size-4"
    assert html =~ "accent-action"
    refute html =~ ~r/<fieldset[^>]*\sdisabled[\s>]/
    refute html =~ ~r/<input[^>]*\sdisabled[\s>]/
  end

  test "the selected option is the only checked control" do
    html = render_component(&group/1, %{value: "dark", disabled: false})

    assert html =~ ~s(id="appearance-dark" name="sample[radio_field]" value="dark" checked)
    refute html =~ ~s(id="appearance-system" name="sample[radio_field]" value="system" checked)
    refute html =~ ~s(id="appearance-light" name="sample[radio_field]" value="light" checked)
  end

  test "disabled groups lock every choice and keep the selected value visible" do
    html = render_component(&group/1, %{value: "system", disabled: true})

    assert html =~ " disabled"
    assert html =~ "cursor-not-allowed"
    assert html =~ "opacity-50"
    assert html =~ ~s(value="system" checked)
  end

  test "radios use the brand-strong focus ring" do
    html = render_component(&group/1, %{value: "light", disabled: false})

    assert html =~ "focus:ring-brand-strong/30"
    assert html =~ "size-4"
  end

  test "a form field supplies name, id, and the selected value" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <.radio_group
            field={@form[:radio_field]}
            label="Appearance"
            options={[{"System", "system"}, {"Light", "light"}]}
          />
          """
        end,
        %{form: to_form(%{"radio_field" => "light"}, as: :sample)}
      )

    assert html =~ ~s(name="sample[radio_field]")
    assert html =~ ~s(value="light" checked)
    refute html =~ ~s(value="system" checked)
  end
end
