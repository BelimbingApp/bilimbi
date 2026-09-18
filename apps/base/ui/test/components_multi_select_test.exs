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
    assert html =~ "hidden peer-aria-expanded:block absolute"
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

  test "aria-expanded starts closed and the trigger toggles it with the list" do
    html =
      render_component(&multi_select_field/1,
        placeholder: "All roles",
        selection_label: "1 role selected|:count roles selected",
        options: [{"Auditor", "1"}, {"Admin", "2"}],
        value: []
      )

    assert html =~ ~s(aria-expanded="false")

    # `aria-haspopup` is ARIA-synonymous with "menu", which promises arrow-key
    # navigation over a `role="menu"`. This list is a disclosure of checkboxes,
    # and `aria-expanded` plus `aria-controls` already say so truthfully.
    refute html =~ "aria-haspopup"

    assert [
             [
               "toggle_attr",
               %{"attr" => ["aria-expanded", "true", "false"], "to" => "#roles-filter"}
             ]
           ] = js_ops(html, "phx-click", "roles-filter")
  end

  test "open is one record: the list and the chevron derive from it, nothing else toggles" do
    html =
      render_component(&multi_select_field/1,
        placeholder: "All roles",
        selection_label: "1 role selected|:count roles selected",
        options: [{"Auditor", "1"}, {"Admin", "2"}],
        value: []
      )

    # A second record could disagree with the first. LiveView writes an
    # attribute op synchronously but defers a class op to a later animation
    # frame, so two activations inside one frame flip an attribute twice and a
    # class once -- an open list announcing `aria-expanded="false"`. That
    # cannot happen to state nobody writes, so every command writes exactly
    # the one attribute and nothing else, however many of them land.
    for {attr, id} <- [
          {"phx-click", "roles-filter"},
          {"data-dismiss", "roles-filter-wrapper"},
          {"data-escape", "roles-filter-wrapper"},
          {"phx-click-away", "roles-filter-wrapper"}
        ] do
      writes = js_ops(html, attr, id) |> Enum.reject(fn [op | _] -> op == "focus" end)

      assert [[_, %{"to" => "#roles-filter"}]] = writes,
             "#{attr} must write only the trigger's aria-expanded, got: #{inspect(writes)}"

      refute Enum.any?(writes, fn [op | _] -> String.contains?(op, "class") end),
             "#{attr} must not carry a class op: derived state cannot be toggled"
    end

    # The list and the chevron read that attribute through the sibling and
    # ancestor relationships the markup already has.
    assert html =~ ~r/id="roles-filter"[^>]*\sclass="peer group /
    assert html =~ ~r/id="roles-filter-options"[^>]*\sclass="hidden peer-aria-expanded:block/
    assert html =~ ~r/id="roles-filter-chevron"[^>]*group-aria-expanded:rotate-180/
  end

  test "the field publishes a close-and-refocus command for Escape from inside it" do
    html =
      render_component(&multi_select_field/1,
        placeholder: "All roles",
        selection_label: "1 role selected|:count roles selected",
        options: [{"Auditor", "1"}, {"Admin", "2"}],
        value: []
      )

    # Not one key binding anywhere in the field: LiveView matches `phx-keydown`
    # on the event target alone, and a match there stops every key -- not only
    # Escape -- reaching the page's `phx-window-keydown` handlers.
    refute html =~ "phx-keydown"
    refute html =~ "phx-key"

    assert [
             ["set_attr", %{"attr" => ["aria-expanded", "false"], "to" => "#roles-filter"}],
             ["focus", %{"to" => "#roles-filter"}]
           ] = js_ops(html, "data-escape", "roles-filter-wrapper")
  end

  test "an outside click closes the list from the wrapper without moving focus" do
    html =
      render_component(&multi_select_field/1,
        placeholder: "All roles",
        selection_label: "1 role selected|:count roles selected",
        options: [{"Auditor", "1"}],
        value: []
      )

    # On the wrapper, not the list: LiveView runs click-away before the click
    # that caused it, so a click-away on the list would close and the trigger
    # would reopen in the same click.
    assert length(Regex.scan(~r/phx-click-away=/, html)) == 1

    assert [
             ["set_attr", %{"attr" => ["aria-expanded", "false"], "to" => "#roles-filter"}]
           ] = js_ops(html, "phx-click-away", "roles-filter-wrapper")
  end

  test "focus leaving the field closes the list without moving focus" do
    html =
      render_component(&multi_select_field/1,
        placeholder: "All roles",
        selection_label: "1 role selected|:count roles selected",
        options: [{"Auditor", "1"}],
        value: []
      )

    # Tabbing past the last option fires no LiveView binding -- it reads
    # `phx-blur` from the element losing focus, never the wrapper -- so the
    # hook watches `focusout` and runs the wrapper's own dismiss command.
    assert html =~ ~s(phx-hook="MultiSelectDismiss")

    ops = js_ops(html, "data-dismiss", "roles-filter-wrapper")

    assert [
             ["set_attr", %{"attr" => ["aria-expanded", "false"], "to" => "#roles-filter"}]
           ] = ops

    refute Enum.any?(ops, fn [op | _] -> op == "focus" end),
           "only Escape returns focus to the trigger"

    # The list takes focus itself, so a click on its padding lands inside the
    # field rather than on `body` and does not read as focus leaving it.
    assert html =~ ~r/id="roles-filter-options"[^>]*\stabindex="-1"/
  end

  defp js_ops(html, attr, id) do
    [value] = Regex.run(~r/id="#{id}"[^>]*\s#{attr}="([^"]*)"/, html, capture: :all_but_first)

    value
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
    |> Jason.decode!()
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
