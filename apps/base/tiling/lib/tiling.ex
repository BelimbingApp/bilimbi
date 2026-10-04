defmodule Bilimbi.Base.Tiling do
  @moduledoc """
  Namespace for the tiled workspace: several Bilimbi pages side by side in
  one browser tab, arranged by a dwindle tree.

  The tree, every operation on it, and the URL codec (`encode/1`, `decode/1`)
  are `Bilimbi.Base.Tiling.Layout`, a pure value module. An account's saved
  layouts and its default are `Bilimbi.Base.Tiling.SavedLayouts`, kept in the
  account's own Settings rows. `Bilimbi.Base.Tiling.Web.WorkspaceLive` is the
  page at `/workspace`. This module owns no tables and performs no I/O of its
  own; it stays so the module descriptor's namespace has a beam.
  """
end
