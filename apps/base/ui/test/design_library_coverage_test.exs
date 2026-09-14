defmodule Bilimbi.Base.UI.DesignLibraryCoverageTest do
  @moduledoc """
  The screens under `/system/design-library` are the human review surface for
  shared UI. This test keeps its component inventory complete.

  Both sides are derived. Components come from Phoenix's `__components__/0`
  reflection, coverage from the shared page source, so neither is a fixture list that
  can drift on its own.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.Components

  @design_library Path.expand("../lib/ui/web/design_library_live.html.heex", __DIR__)

  test "every public component appears in the Design Library" do
    source = File.read!(@design_library)

    missing =
      public_components()
      |> Enum.reject(&(source =~ "<.#{&1}"))
      |> Enum.sort()

    assert missing == [],
           """
           These components are public in Bilimbi.Base.UI.Components but never
           rendered in the Design Library:

               #{Enum.map_join(missing, ", ", &"<.#{&1}>")}

           Add an example to
           apps/base/ui/lib/ui/web/design_library_live.html.heex. A component
           missing from the human review surface is a component nobody can
           validate in context.
           """
  end

  # `__components__/0` also reports internals — `error/1` and
  # `table_sort_heading/1` are called only by other components and have no
  # business on the Design Library page. Public means callable from another
  # module.
  defp public_components do
    Components.__components__()
    |> Map.keys()
    |> Enum.filter(&function_exported?(Components, &1, 1))
  end
end
