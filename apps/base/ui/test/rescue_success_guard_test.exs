defmodule Bilimbi.Base.UI.RescueSuccessGuardTest do
  @moduledoc """
  A `rescue` clause whose body is a success value converts failure into success
  by construction, and there is no case where that is what anyone wanted.

  #409: `Core.Employee.Web.ShowLive` linked a user account through

      rescue
        _ -> {:ok, nil}

  so a constraint violation, a missing table or an authz raise all reported the
  link as done. The caller's `{:error, _}` branch — which flashes the failure —
  was unreachable for every one of them.

  It is the write-path form of #359, where a rescued `Ecto.QueryError` for a
  missing `base_settings` table rendered as `nil`, `nil` happened to be the value
  that renders correctly, and fifteen dashboard tests passed in CI while every
  real account saw an empty dashboard.

  Derived, not a fixture: it reads the tree, so it cannot pass by being edited
  alongside the thing it guards. That was #201's failure mode.

  **What this does not check.** Only the one-line clause body — `_ -> :ok`,
  `_ -> {:ok, _}`, `_ -> true` — directly after `rescue`. A multi-line rescue
  body that ends in a success value is not detected. That is the shape that has
  actually occurred; a fuller check would need the AST.

  Degrading to `[]` or `{:error, _}` is out of scope by design. Both are visible
  to the caller, and whether they are right is a review question, not a
  mechanical one.
  """

  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)

  # Tracked debt, not endorsement. An exemption listed here makes the test fail
  # once its defect is resolved, so exemptions cannot outlive their fix (#413).
  @tracked []

  @success_body ~r/rescue\s*\n(\s*[^\n]*->\s*(?:\{:ok\b|:ok\b|true\b)[^\n]*)/

  test "no rescue clause reports a failure as a success" do
    offenders =
      @workspace_root
      |> Path.join("apps/*/*/lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(&success_returning_rescues/1)
      |> Enum.sort()

    located = Map.new(offenders, fn offender -> {location(offender), offender} end)

    new = for {loc, offender} <- located, loc not in @tracked, do: offender
    fixed = @tracked -- Map.keys(located)

    assert new == [],
           """
           These rescue a failure and hand the caller a success:

           #{Enum.map_join(new, "\n", &("    " <> &1))}

           Let the failure reach the caller. If the module may genuinely be
           absent, answer that with `Code.ensure_loaded?/1` and an explicit
           branch — not by catching everything the call can raise.
           """

    assert fixed == [],
           """
           These are listed as tracked exemptions but no longer offend:

           #{Enum.map_join(fixed, "\n", &("    " <> &1))}

           Delete them from @tracked. An exemption that outlives its defect is
           how the next real one gets waved through.
           """
  end

  # "apps/x/y.ex:12  _ -> :ok" -> "apps/x/y.ex:12"
  defp location(offender), do: offender |> String.split("  ") |> hd()

  defp success_returning_rescues(path) do
    source = File.read!(path)
    relative = Path.relative_to(path, @workspace_root)

    @success_body
    |> Regex.scan(source, return: :index)
    |> Enum.map(fn [{whole_start, _}, {body_start, body_len}] ->
      line = source |> binary_part(0, whole_start) |> count_newlines() |> Kernel.+(1)
      body = source |> binary_part(body_start, body_len) |> String.trim()
      # The clause sits on the line after `rescue`.
      "#{relative}:#{line + 1}  #{body}"
    end)
  end

  defp count_newlines(binary) do
    binary |> :binary.matches("\n") |> length()
  end
end
