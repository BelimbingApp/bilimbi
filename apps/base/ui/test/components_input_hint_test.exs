defmodule Bilimbi.Base.UI.ComponentsInputHintTest do
  @moduledoc """
  Helper text belongs inside the field wrapper.

  A `<p>` placed after `<.input>` sits outside the wrapper that owns `mb-4`,
  so callers compensated with four different spacings — `mt-1`, `mt-1 mb-4`,
  `mt-0.5`, and a negative `-mt-2 mb-4`. On Create Role the result was a hint
  crammed against the next field's label while its neighbour had clear space
  (#279).

  Nothing else can catch this: every one of those variants renders the correct
  *text*, so string assertions pass whether the gap is 16px or zero.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp field(assigns) do
    ~H"""
    <.input id="f" name="f" value="" type="text" label="Code" hint={@hint} errors={@errors} />
    """
  end

  test "the hint renders inside the wrapper, not after it" do
    html = render_component(&field/1, hint: "Lowercase letters only.", errors: [])

    assert html =~ "Lowercase letters only."

    # Position, not adjacency. My first version checked what followed the hint
    # *text* and always saw `</p>` first, so it passed with the hint emitted
    # outside the wrapper -- the very bug this guards.
    {hint_at, _} = :binary.match(html, "Lowercase letters only.")
    wrapper_close_at = byte_size(html) - byte_size("</div>")

    assert hint_at < wrapper_close_at,
           """
           The hint escaped the field wrapper.

           Spacing must come from the wrapper, or every caller invents its own
           margin again (#279).
           """

    assert String.ends_with?(String.trim(html), "</div>"),
           "the wrapper must still be the outermost element"
  end

  test "no hint means no empty paragraph" do
    html = render_component(&field/1, hint: nil, errors: [])

    # Matching on "text-ink-subtle" alone is not enough: `field_class/3`
    # already carries `disabled:text-ink-subtle` on every input, so that
    # assertion passes for the wrong reason. Match the hint paragraph itself.
    refute html =~ ~s(<p class="mt-1.5),
           "a nil hint must not leave an empty helper paragraph behind"
  end

  test "the hint sits above the error, so the error is what the eye lands on" do
    html = render_component(&field/1, hint: "Lowercase letters only.", errors: ["is required"])

    hint_at = :binary.match(html, "Lowercase letters only.") |> elem(0)
    error_at = :binary.match(html, "is required") |> elem(0)

    assert hint_at < error_at
  end
end
