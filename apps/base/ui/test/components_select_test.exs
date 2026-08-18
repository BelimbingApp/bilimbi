defmodule Bilimbi.Base.UI.ComponentsSelectTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp select_field(assigns) do
    ~H"""
    <.input
      id="test-select"
      name="category"
      type="select"
      label="Category"
      prompt={@prompt}
      options={@options}
      value={@value}
    />
    """
  end

  test "renders select prompt with selected attribute when value is empty or nil" do
    html_nil =
      render_component(&select_field/1,
        prompt: "Choose category",
        options: [{"Engineering", "eng"}, {"Design", "des"}],
        value: nil
      )

    assert html_nil =~ ~s(<option value="" selected>Choose category</option>)

    html_empty =
      render_component(&select_field/1,
        prompt: "Choose category",
        options: [{"Engineering", "eng"}, {"Design", "des"}],
        value: ""
      )

    assert html_empty =~ ~s(<option value="" selected>Choose category</option>)
  end

  test "renders select prompt without selected attribute when a value is selected" do
    html =
      render_component(&select_field/1,
        prompt: "Choose category",
        options: [{"Engineering", "eng"}, {"Design", "des"}],
        value: "eng"
      )

    assert html =~ ~s(<option value="">Choose category</option>)
    assert html =~ ~s(<option selected value="eng">Engineering</option>)
  end
end
