defmodule Bilimbi.Base.UI.CapabilityCheckSpellingTest do
  @moduledoc """
  Capability checks must go through `Bilimbi.Base.UI.allowed?/2`.

  The predicate guards on `is_list/1` and returns `false` for a mis-shaped
  scope. The hand-rolled spelling — `"some.capability" in scope.capabilities` —
  **raises** when `capabilities` is `nil` or absent, which in a template is a
  crashed page rather than a hidden control.

  #229 consolidated three copies of the *definition*, and a grep for
  `def allowed?` reported the job done. It was not: five call sites spelled the
  check inline and were invisible to that search (#231). This test looks for the
  spelling instead, so the next one fails here rather than in production.
  """

  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)

  # `Authz.Evaluator` compares against the capability *registry*, not a scope's
  # granted list, so it is a different question and legitimately spelled this way.
  @allowed_paths ["apps/base/authz/lib/authz/evaluator.ex"]

  test "no screen hand-rolls a capability check" do
    offenders =
      @workspace_root
      |> Path.join("apps/*/*/lib/**/*.{ex,heex}")
      |> Path.wildcard()
      |> Enum.reject(&exempt?/1)
      |> Enum.flat_map(&inline_checks/1)
      |> Enum.sort()

    assert offenders == [],
           """
           These check a capability by hand instead of calling allowed?/2:

           #{Enum.map_join(offenders, "\n", &("    " <> &1))}

           `x in scope.capabilities` raises when capabilities is nil;
           `allowed?(scope, x)` returns false. In a template that is the
           difference between a hidden control and a crashed page.
           """
  end

  defp exempt?(path) do
    relative = Path.relative_to(path, @workspace_root)
    relative in @allowed_paths or String.ends_with?(relative, "/ui.ex")
  end

  defp inline_checks(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    # Field access only. `x in capabilities()` asks whether a capability is
    # *known to the registry*, which is a different question and legitimately
    # spelled that way -- `Authz.capability_known?/1` does exactly that.
    |> Enum.filter(fn {line, _number} -> line =~ ~r/\bin\s+[@\w.\[\]]*\.capabilities\b/ end)
    |> Enum.map(fn {_line, number} ->
      "#{Path.relative_to(path, @workspace_root)}:#{number}"
    end)
  end
end
