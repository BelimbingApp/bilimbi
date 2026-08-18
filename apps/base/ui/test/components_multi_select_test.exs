defmodule Bilimbi.Base.UI.ComponentsMultiSelectTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp multi_select_field(assigns) do
    ~H"""
    <.multi_select
      id="roles-filter"
      name="roles"
      label="Roles"
      placeholder={@placeholder}
      selection_label={@selection_label}
      options={@options}
      value={@value}
    />
    """
  end

  test "renders placeholder when no options are selected" do
    html =
      render_component(&multi_select_field/1,
        placeholder: "All roles",
        selection_label: "1 role selected|:count roles selected",
        options: [{"Auditor", "1"}, {"Admin", "2"}],
        value: []
      )

    assert html =~ "All roles"
    assert html =~ ~s(id="roles-filter-options")
    assert html =~ ~s(id="roles-filter-option-1")
    assert html =~ ~s(id="roles-filter-option-2")
    refute html =~ "checked"
  end

  test "renders singular selection label when 1 option is selected" do
    html =
      render_component(&multi_select_field/1,
        placeholder: "All roles",
        selection_label: "1 role selected|:count roles selected",
        options: [{"Auditor", "1"}, {"Admin", "2"}],
        value: ["1"]
      )

    assert html =~ "1 role selected"
    assert html =~ ~s(id="roles-filter-option-1" name="roles[]" value="1" checked)
    refute html =~ ~s(id="roles-filter-option-2" name="roles[]" value="2" checked)
  end

  test "renders plural selection label when multiple options are selected" do
    html =
      render_component(&multi_select_field/1,
        placeholder: "All roles",
        selection_label: "1 role selected|:count roles selected",
        options: [{"Auditor", "1"}, {"Admin", "2"}, {"Editor", "3"}],
        value: ["1", "3"]
      )

    assert html =~ "2 roles selected"
    assert html =~ ~s(id="roles-filter-option-1" name="roles[]" value="1" checked)
    assert html =~ ~s(id="roles-filter-option-3" name="roles[]" value="3" checked)
  end

  test "renders empty state message when options list is empty" do
    html =
      render_component(&multi_select_field/1,
        placeholder: "All roles",
        selection_label: "1 role selected|:count roles selected",
        options: [],
        value: []
      )

    assert html =~ "All roles"
    assert html =~ "No options available."
  end
end
