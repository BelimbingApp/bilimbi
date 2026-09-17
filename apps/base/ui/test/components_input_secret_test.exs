defmodule Bilimbi.Base.UI.ComponentsInputSecretTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp secret_field(assigns) do
    assigns =
      assigns
      |> assign_new(:disabled, fn -> false end)
      |> assign_new(:class, fn -> nil end)

    ~H"""
    <.input
      id="api-key"
      name="api_key"
      type="password"
      label="API key"
      value="sk-sample"
      reveal={@reveal}
      class={@class}
      disabled={@disabled}
    />
    """
  end

  defp field_class(html) do
    [value] =
      Regex.run(~r/<input type="password"[^>]*\sid="api-key"[^>]*\sclass="([^"]*)"/, html,
        capture: :all_but_first
      )

    String.split(value, ~r/\s+/, trim: true)
  end

  # Matches only while the input and the control are adjacent children of one
  # row, which is what makes the control's placement follow the input's box.
  defp reveal_row(html) do
    [row, control] =
      Regex.run(
        ~r|<div class="([^"]*)">\s*<input type="password"[^>]*\sid="api-key"[^>]*>\s*<button id="api-key-reveal"[^>]*\sclass="([^"]*)"|,
        html,
        capture: :all_but_first
      )

    {String.split(row, ~r/\s+/, trim: true), String.split(control, ~r/\s+/, trim: true)}
  end

  defp glyph_class(html, id) do
    [value] = Regex.run(~r/<span id="#{id}" class="([^"]*)"/, html, capture: :all_but_first)

    String.split(value, ~r/\s+/, trim: true)
  end

  defp js_ops(html, attr, id) do
    [value] = Regex.run(~r/id="#{id}"[^>]*\s#{attr}="([^"]*)"/, html, capture: :all_but_first)

    value
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
    |> Jason.decode!()
  end

  test "a password input stays masked with no control by default" do
    html = render_component(&secret_field/1, reveal: false)

    assert html =~ ~s(type="password")
    refute html =~ ~s(id="api-key-reveal")
    refute html =~ "pr-10"
  end

  test "reveal renders a real button whose name states the action and the current state" do
    html = render_component(&secret_field/1, reveal: true)

    assert html =~ ~s(<button id="api-key-reveal" type="button")
    assert html =~ ~s(aria-label="Show secret, currently hidden")
    assert html =~ ~s(aria-controls="api-key")
    assert html =~ ~s(title="Show secret")
    assert html =~ ~s(phx-hook="SecretReveal")
    assert html =~ "pr-10"
    assert html =~ "hero-eye"
    assert html =~ "hero-eye-slash"
  end

  test "the toggle swaps the input type, the accessible name, the title and the glyph together" do
    html = render_component(&secret_field/1, reveal: "password")

    assert html =~ ~s(aria-label="Show password, currently hidden")

    ops = js_ops(html, "phx-click", "api-key-reveal")

    assert [
             ["toggle_attr", %{"attr" => ["type", "text", "password"], "to" => "#api-key"}],
             [
               "toggle_attr",
               %{
                 "attr" => [
                   "aria-label",
                   "Hide password, currently shown",
                   "Show password, currently hidden"
                 ]
               }
             ],
             ["toggle_attr", %{"attr" => ["title", "Hide password", "Show password"]}],
             [
               "toggle_class",
               %{"names" => ["hidden"], "to" => "#api-key-reveal-show, #api-key-reveal-hide"}
             ]
           ] = ops

    refute Enum.any?(ops, fn [op | _] -> op == "focus" end),
           "the toggle must not move focus; the hook keeps a pointer press in the input"
  end

  test "the two glyphs differ only by `hidden`, so the control holds still as it toggles" do
    html = render_component(&secret_field/1, reveal: true)

    show = glyph_class(html, "api-key-reveal-show")
    hide = glyph_class(html, "api-key-reveal-hide")

    # The toggle moves `hidden` and nothing else, so any other difference
    # between the two spans survives the swap and moves the icon.
    assert "hidden" in hide
    refute "hidden" in show
    assert hide -- ["hidden"] == show
  end

  test "the control is placed against the input's own box, not a box the caller cannot size" do
    narrowed = render_component(&secret_field/1, reveal: true, class: "w-64 border px-3 py-1")
    default = render_component(&secret_field/1, reveal: true)

    {narrowed_row, narrowed_control} = reveal_row(narrowed)
    {default_row, default_control} = reveal_row(default)

    # The control follows the input in a flex row and is pulled back over the
    # padding the input reserves, so it lands from the input's own used width.
    # Nothing here reads a width, which is why both renders are identical: a
    # caller replacing the field class moves the input and the control alike.
    assert "flex" in narrowed_row
    assert "items-center" in narrowed_row
    assert "-ml-[1.875rem]" in narrowed_control
    assert narrowed_row == default_row
    assert narrowed_control == default_control

    # An offset against an ancestor box would be the bug: that box is the full
    # width of the field wrapper whatever the caller sized the input to.
    refute "absolute" in narrowed_control
    refute "relative" in narrowed_row

    # The space it sits in is still reserved inside the field.
    classes = field_class(narrowed)

    assert "pr-10" in classes
    assert "w-64" in classes
    refute "block" in classes
  end

  test "a disabled input disables its reveal control" do
    html = render_component(&secret_field/1, reveal: true, disabled: true)

    assert html =~ ~r/<button id="api-key-reveal"[^>]*\sdisabled/
  end

  test "reveal on a non-password input is a caller error" do
    assert_raise ArgumentError, ~r/reveal only applies to a password input/, fn ->
      render_component(&input/1, id: "email", name: "email", type: "email", reveal: true)
    end
  end
end
