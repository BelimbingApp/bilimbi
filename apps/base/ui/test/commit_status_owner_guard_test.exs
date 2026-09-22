defmodule Bilimbi.Base.UI.CommitStatusOwnerGuardTest do
  @moduledoc """
  The commit-status bookkeeping has one owner, `Bilimbi.Base.UI.CommitStatus`.

  Before it existed, the address and user detail pages each carried the same
  bookkeeping character for character: dropping a stale "Saved" when a newer
  commit starts, the refusal wording, the rejected-value truncation limit and
  the inline field resolver. A third adopter would have copied it a third
  time. This test looks for those spellings in web adapters so the next copy
  fails here rather than drifting in production.
  """

  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)

  # Each pattern is a spelling only the owner may carry.
  @owner_only [
    ~r/defp?\s+put_field_status\(/,
    ~r/defp?\s+drop_saved\(/,
    ~r/defp?\s+rejected_value\(/,
    ~r/@rejected_value_limit\b/,
    ~r/defp?\s+inline_field\(/,
    ~r/value == :saved/,
    ~r/Try again, and tell your administrator if it keeps failing/
  ]

  test "no web adapter keeps its own commit-status bookkeeping" do
    offenders =
      @workspace_root
      |> Path.join("apps/*/*/lib/**/web/**/*.{ex,heex}")
      |> Path.wildcard()
      |> Enum.flat_map(&copies/1)
      |> Enum.sort()

    assert offenders == [],
           """
           These carry commit-status bookkeeping that Bilimbi.Base.UI.CommitStatus owns:

           #{Enum.map_join(offenders, "\n", &("    " <> &1))}

           Call CommitStatus.put/3, write_forbidden/2, inline_field/2,
           refusal_message/4 and failure_message/0 instead of restating them.
           """
  end

  defp copies(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _number} -> Enum.any?(@owner_only, &Regex.match?(&1, line)) end)
    |> Enum.map(fn {_line, number} -> "#{Path.relative_to(path, @workspace_root)}:#{number}" end)
  end
end
