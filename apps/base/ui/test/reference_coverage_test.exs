defmodule Bilimbi.Base.UI.ReferenceCoverageTest do
  @moduledoc """
  `/system/ui-reference` is the canonical component reference (#235, #236).

  Nothing otherwise keeps it complete: add a component to
  `Bilimbi.Base.UI.Components` and the reference silently stops covering
  everything — no test, no gate, and the page still looks finished. Same shape
  as the icon safelist (#219) and the descriptor mirror (#201).

  Both sides are derived. Components come from Phoenix's `__components__/0`
  reflection, coverage from the page source, so neither is a fixture list that
  can drift on its own.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.Components

  @reference Path.expand("../lib/ui/web/reference_live.html.heex", __DIR__)

  test "every public component appears in the UI reference" do
    source = File.read!(@reference)

    missing =
      public_components()
      |> Enum.reject(&(source =~ "<.#{&1}"))
      |> Enum.sort()

    assert missing == [],
           """
           These components are public in Bilimbi.Base.UI.Components but never
           rendered in the UI reference:

               #{Enum.map_join(missing, ", ", &"<.#{&1}>")}

           Add an example to apps/base/ui/lib/ui/web/reference_live.html.heex.
           The reference is the page people are told to read before building a
           screen; a component missing from it is a component nobody finds.
           """
  end

  # `__components__/0` also reports internals — `error/1` and
  # `table_sort_heading/1` are called only by other components and have no
  # business on a reference page. Public means callable from another module.
  defp public_components do
    Components.__components__()
    |> Map.keys()
    |> Enum.filter(&function_exported?(Components, &1, 1))
  end
end
