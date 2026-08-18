defmodule Bilimbi.Base.UI.PageContainerGuardTest do
  @moduledoc """
  A screen's content width is `<.page>`'s decision, not the screen's.

  #287 found twelve list screens using four widths, fixed all eighteen
  containers, and wrote the rule into `DESIGN.md`:

      Never hand-write `mx-auto max-w-*` on a screen's root container.

  That sentence holds only as long as the next person has read it. This test
  is what makes it hold anyway — the same reason the icon safelist (#219), the
  descriptor mirror (#201) and the capability spelling (#231) each needed one
  after the convention alone decayed.

  Derived, not a fixture: it reads the tree, so it cannot pass by being edited
  alongside the thing it guards. That was #201's exact failure mode.
  """

  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)

  # `Components.page/1` is where the widths live, so it is the one file that
  # must pair `mx-auto` with a `max-w-*`. The UI reference renders miniature
  # previews of the variants rather than using them as its own container.
  @allowed_paths [
    "apps/base/ui/lib/ui/components.ex",
    "apps/base/ui/lib/ui/web/reference_live.html.heex"
  ]

  test "no screen hand-writes its own page width" do
    offenders =
      @workspace_root
      |> Path.join("apps/*/*/lib/**/*.{ex,heex}")
      |> Path.wildcard()
      |> Enum.reject(&exempt?/1)
      |> Enum.flat_map(&hand_written_containers/1)
      |> Enum.sort()

    assert offenders == [],
           """
           These choose a page width instead of letting <.page> choose it:

           #{Enum.map_join(offenders, "\n", &("    " <> &1))}

           DESIGN.md: "Never hand-write `mx-auto max-w-*` on a screen's root
           container." Use <.page variant={:list | :form | :detail}> so the
           width stays one decision instead of eighteen (#287, #289).
           """
  end

  defp exempt?(path) do
    Path.relative_to(path, @workspace_root) in @allowed_paths
  end

  # Both classes on one element is the signature of a centred page container.
  # `mx-auto` alone centres plenty of legitimate things (a spinner, an empty
  # state); `max-w-*` alone constrains prose. Only the pair is the rule.
  defp hand_written_containers(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _number} ->
      line =~ ~r/class=[^>]*\bmx-auto\b/ and line =~ ~r/class=[^>]*\bmax-w-[a-z0-9]+\b/
    end)
    |> Enum.map(fn {_line, number} ->
      "#{Path.relative_to(path, @workspace_root)}:#{number}"
    end)
  end
end
