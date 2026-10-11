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

  @doc """
  Whether the authorized company may take a settings write.

  `authorize/2` admits a reader to a company's settings; this is asked again
  before each save or restore. An archived company is read-only for good:
  `{:error, :company_archived}`, which the editor reports in those words.
  """
  @callback writable(map(), pos_integer()) :: :ok | {:error, atom()}
end
