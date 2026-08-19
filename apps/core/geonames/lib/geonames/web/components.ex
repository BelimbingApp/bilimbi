defmodule Bilimbi.Core.Geonames.Web.Components do
  @moduledoc false

  use Bilimbi.Base.UI, :html

  @doc """
  Formats an integer with thousands separator commas.
  """
  def format_integer(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  def format_integer(_value), do: "—"
end
