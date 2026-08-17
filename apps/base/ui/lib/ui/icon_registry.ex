defmodule Bilimbi.Base.UI.IconRegistry do
  @moduledoc """
  Small registry for Bilimbi-owned SVG icons not available in Heroicons.

  Heroicons continue to use the generated `hero-*` utilities. Add an entry
  here only when a product-specific glyph is needed so every caller can still
  render it through `<.icon>`.
  """

  @type icon :: %{
          view_box: String.t(),
          fill: String.t(),
          paths: [String.t()]
        }

  @icons %{
    "bilimbi-pin" => %{
      view_box: "0 0 24 24",
      fill: "none",
      paths: [
        "M16.114 1.553l6.333 6.333a1.75 1.75 0 0 1-.603 2.869l-1.63.633a5.67 5.67 0 0 0-3.395 3.725l-1.131 3.959a1.75 1.75 0 0 1-2.92.757L9 16.061 7.939 15l-3.768-3.768a1.75 1.75 0 0 1 .757-2.92l3.959-1.131a5.666 5.666 0 0 0 3.725-3.395l.633-1.63a1.75 1.75 0 0 1 2.869-.603Z",
        "M9 16.061L3.405 21.655"
      ]
    }
  }

  @spec fetch(String.t()) :: {:ok, icon()} | :error
  def fetch(name) when is_binary(name), do: Map.fetch(@icons, name)
  def fetch(_name), do: :error
end
