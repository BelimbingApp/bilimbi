defmodule Bilimbi.Base.UI.ComponentsInputStatesTest do
  @moduledoc """
  Field states a person depends on: required marking, invalid marking, and
  the association between a control and its hint and error text.

  These tests assert behaviour and relationships — that the control itself
  carries the invalid marking, that `aria-describedby` points at elements
  that exist and hold the hint and error text.

  Readonly paint is the one exception. A locked background has no evidence
  beyond the class that draws it, so that test matches the class, anchored
  on its boundaries so it cannot be satisfied by the `disabled:` variant
  every field already carries.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp field(assigns) do
    assigns = assign_new(assigns, :type, fn -> "text" end)

    ~H"""
    <.input
      id="f"
      name="f"
      value=""
      type={@type}
      label="Code"
      hint={@hint}
      errors={@errors}
      required={@required}
      readonly={@readonly}
    />
    """
  end

  defp select_field(assigns) do
    ~H"""
    <.input
      id="s"
      name="s"
      type="select"
      label="Category"
      options={[{"Engineering", "eng"}]}
      value={@value}
      hint={@hint}
      errors={@errors}
    />
    """
  end

  defp textarea_field(assigns) do
    ~H"""
    <.input
      id="t"
      name="t"
      type="textarea"
      label="Notes"
      value=""
      hint={@hint}
      errors={@errors}
    />
    """
  end

  defp checkbox_field(assigns) do
    ~H"""
    <.input
      id="c"
      name="c"
      type="checkbox"
      label="Enable"
      value="false"
      hint={@hint}
      errors={@errors}
    />
    """
  end

  defp multi_select_field(assigns) do
    ~H"""
    <.multi_select
      id="m"
      name="m"
      label="Roles"
      options={[{"Administrator", "admin"}]}
      value={[]}
      hint={@hint}
      errors={@errors}
      required={@required}
    />
    """
  end

  defp multi_select_through_input(assigns) do
    ~H"""
    <.input
      id="m"
      name="m"
      type="multi_select"
      label="Roles"
      value={[]}
      options={[{"Administrator", "admin"}]}
      hint={@hint}
      errors={@errors}
      required={@required}
    />
    """
  end

  defp control_tag(html, id, tag \\ "input") do
    assert [match] = Regex.run(~r/<#{tag}[^>]*id="#{id}"[^>]*>/, html),
           "expected a <#{tag}> control with id=#{id} in:\n#{html}"

    match
  end

  defp label_tag(html, id \\ "f") do
    assert [match] = Regex.run(~r/<label[^>]*for="#{id}"[^>]*>.*?<\/label>/s, html),
           "expected a label for the field in:\n#{html}"

    match
  end

  test "an invalid field marks its own control invalid" do
    html =
      render_component(&field/1,
        hint: nil,
        errors: ["can't be blank"],
        required: nil,
        readonly: nil
      )

    assert control_tag(html, "f") =~ ~s(aria-invalid="true")
  end

  test "a valid field carries no invalid marking" do
    html =
      render_component(&field/1, hint: nil, errors: [], required: nil, readonly: nil)

    refute html =~ "aria-invalid"
  end

  test "hint and error text are both associated with the control" do
    html =
      render_component(&field/1,
        hint: "Lowercase letters only.",
        errors: ["can't be blank"],
        required: nil,
        readonly: nil
      )

    tag = control_tag(html, "f")

    assert tag =~ ~s(aria-describedby="f-hint f-error-0")

    # The referenced ids must exist and hold the text they promise: a
    # dangling reference announces nothing.
    assert html =~ ~r/id="f-hint"[^>]*>Lowercase letters only\./
    assert html =~ ~r/id="f-error-0"[^>]*>.*can&#39;t be blank/s
  end

  test "a hint alone is associated with the control" do
    html =
      render_component(&field/1,
        hint: "Lowercase letters only.",
        errors: [],
        required: nil,
        readonly: nil
      )

    assert control_tag(html, "f") =~ ~s(aria-describedby="f-hint")
    assert html =~ ~r/id="f-hint"[^>]*>Lowercase letters only\./
  end

  test "an error alone is associated with the control" do
    html =
      render_component(&field/1,
        hint: nil,
        errors: ["can't be blank"],
        required: nil,
        readonly: nil
      )

    assert control_tag(html, "f") =~ ~s(aria-describedby="f-error-0")
    assert html =~ ~r/id="f-error-0"[^>]*>.*can&#39;t be blank/s
  end

  test "no hint and no error leaves no dangling association" do
    html =
      render_component(&field/1, hint: nil, errors: [], required: nil, readonly: nil)

    refute html =~ "aria-describedby"
  end

  test "a required field visibly marks its label required" do
    html =
      render_component(&field/1,
        hint: nil,
        errors: [],
        required: true,
        readonly: nil
      )

    label = label_tag(html)

    # The visible cue a person depends on. It is hidden from assistive
    # technology because the control's own `required` attribute already
    # announces it; a raw "*" would be read aloud as "star".
    assert label =~ ~s(<span aria-hidden="true">*</span>)
    assert control_tag(html, "f") =~ ~r/\srequired(\s|=|>|\/)/
  end

  test "an optional field carries no required marker" do
    html =
      render_component(&field/1, hint: nil, errors: [], required: nil, readonly: nil)

    refute label_tag(html) =~ "aria-hidden"
  end

  test "a readonly field keeps its value submittable, unlike a disabled one" do
    html =
      render_component(&field/1,
        hint: nil,
        errors: [],
        required: nil,
        readonly: true
      )

    tag = control_tag(html, "f")

    # Match the attributes themselves: a bare substring also hits the
    # `disabled:` styling variant. A disabled control would not submit its
    # value, which is the behaviour this distinguishes.
    assert tag =~ ~r/\sreadonly(\s|=|>|\/)/
    refute tag =~ ~r/\sdisabled(\s|=|>|\/)/
  end

  test "an invalid select marks its own control invalid and associated" do
    html =
      render_component(&select_field/1,
        value: nil,
        hint: "Pick one.",
        errors: ["can't be blank"]
      )

    tag = control_tag(html, "s", "select")
    assert tag =~ ~s(aria-invalid="true")
    assert tag =~ ~s(aria-describedby="s-hint s-error-0")
  end

  test "an invalid textarea marks its own control invalid and associated" do
    html =
      render_component(&textarea_field/1,
        hint: "Plain text.",
        errors: ["can't be blank"]
      )

    tag = control_tag(html, "t", "textarea")
    assert tag =~ ~s(aria-invalid="true")
    assert tag =~ ~s(aria-describedby="t-hint t-error-0")
  end

  test "only a field the caller marked readonly is painted locked" do
    locked =
      render_component(&field/1, hint: nil, errors: [], required: nil, readonly: true)

    editable =
      render_component(&field/1, hint: nil, errors: [], required: nil, readonly: nil)

    select = render_component(&select_field/1, value: nil, hint: nil, errors: [])

    assert control_tag(locked, "f") =~ ~r/[\s"]bg-surface-sunken[\s"]/
    refute control_tag(editable, "f") =~ ~r/[\s"]bg-surface-sunken[\s"]/

    # HTML has no readonly `select`: the attribute does not apply, so a
    # dropdown must never be painted from readonliness. The CSS `:read-only`
    # pseudo-class matches every one of them, which is why the state is read
    # from the attribute the caller set instead.
    select_tag = control_tag(select, "s", "select")
    refute select_tag =~ "read-only"
    refute select_tag =~ ~r/[\s"]bg-surface-sunken[\s"]/
  end

  test "an invalid multi-select marks its own control invalid and associated" do
    html =
      render_component(&multi_select_field/1,
        hint: "Pick at least one.",
        errors: ["can't be blank"],
        required: false
      )

    tag = control_tag(html, "m", "button")

    assert tag =~ ~s(aria-invalid="true")
    assert tag =~ ~s(aria-describedby="m-hint m-error-0")
    assert html =~ ~r/id="m-hint"[^>]*>Pick at least one\./
    assert html =~ ~r/id="m-error-0"[^>]*>.*can&#39;t be blank/s
  end

  test "a valid multi-select carries no invalid marking or dangling association" do
    html =
      render_component(&multi_select_field/1, hint: nil, errors: [], required: false)

    refute html =~ "aria-invalid"
    refute html =~ "aria-describedby"
  end

  test "a required multi-select marks its label and announces the requirement" do
    html =
      render_component(&multi_select_field/1, hint: nil, errors: [], required: true)

    assert label_tag(html, "m") =~ ~s(<span aria-hidden="true">*</span>)
    assert control_tag(html, "m", "button") =~ ~s(aria-required="true")
  end

  test "a required multi-select reached through <.input> is marked the same way" do
    html =
      render_component(&multi_select_through_input/1,
        hint: nil,
        errors: [],
        required: true
      )

    assert label_tag(html, "m") =~ ~s(<span aria-hidden="true">*</span>)

    # `required` is not a conforming attribute on a button, so the global must
    # be consumed rather than splatted onto the trigger.
    refute control_tag(html, "m", "button") =~ ~r/[\s]required(\s|=|>|\/)/
  end

  test "an optional multi-select carries no required marker" do
    html =
      render_component(&multi_select_field/1, hint: nil, errors: [], required: false)

    refute label_tag(html, "m") =~ "aria-hidden"
    refute html =~ "aria-required"
  end

  test "an invalid checkbox marks its own control invalid and associated" do
    html =
      render_component(&checkbox_field/1,
        hint: "Required for sync.",
        errors: ["must be accepted"]
      )

    tag = control_tag(html, "c")
    assert tag =~ ~s(aria-invalid="true")
    assert tag =~ ~s(aria-describedby="c-hint c-error-0")
  end
end
