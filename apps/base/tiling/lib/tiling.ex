defmodule Bilimbi.Base.Tiling do
  @moduledoc """
  Public API of the tiled workspace: several Bilimbi pages side by side in
  one browser tab, arranged by a dwindle tree.

  The tree and every operation on it are `Bilimbi.Base.Tiling.Layout`, a
  pure value module. An account's saved layouts and its default are
  `Bilimbi.Base.Tiling.SavedLayouts`, kept in the account's own Settings
  rows. `Bilimbi.Base.Tiling.Web.WorkspaceLive` is the page at `/workspace`.
  This module owns no tables and performs no I/O of its own.
  """

  alias Bilimbi.Base.Tiling.Layout

  @doc "The most tiles one workspace holds."
  @spec max_tiles() :: pos_integer()
  defdelegate max_tiles, to: Layout

  @doc "Reads a workspace tree from its URL form."
  @spec decode(String.t()) :: {:ok, Layout.t()} | :error
  defdelegate decode(encoded), to: Layout

  @doc "The URL form of a workspace tree."
  @spec encode(Layout.t()) :: String.t()
  defdelegate encode(layout), to: Layout
end
