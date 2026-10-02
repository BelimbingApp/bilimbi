defmodule Bilimbi.Base.Settings.CompanyScopeService do
  @moduledoc """
  Host seam for the shared company's settings editor.

  Base never resolves Core companies itself. The host lists live companies
  the authenticated actor may manage and rechecks the selected target before
  each operation. A company view must include only definitions allowing
  `:company`; Form's fallback to global is for inheritance, not write reach.
  """

  alias Bilimbi.Base.Settings.Scope

  @callback companies(map()) :: [%{id: pos_integer(), name: String.t()}]
  @callback authorize(map(), pos_integer()) :: {:ok, Scope.t()} | {:error, atom()}
end
