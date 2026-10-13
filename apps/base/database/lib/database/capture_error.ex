defmodule Bilimbi.Base.Database.CaptureError do
  @moduledoc """
  A strict capture failure. Diagnostics contain types and identity, never values.
  """

  defexception [:action, :schema, :error_type]

  @impl true
  def message(error) do
    "audit capture failed for #{inspect(error.schema)} #{error.action}: #{inspect(error.error_type)}"
  end
end
