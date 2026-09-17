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

  test "a caller's own field class still reserves the space the control sits in" do
    html = render_component(&secret_field/1, reveal: true, class: "w-64 border px-3 py-1")

    classes = field_class(html)

    # The control is positioned inside the field, so its space is structural:
    # replacing the field's look must not run the secret underneath the eye.
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
