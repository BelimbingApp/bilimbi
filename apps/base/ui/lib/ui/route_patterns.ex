defmodule Bilimbi.Base.UI.RoutePatterns do
  @moduledoc false

  @doc """
  Returns true when `split_path` (Phoenix path_info) matches a route path.

  Segments that start with `:` are wildcards. The root path `"/"` matches `[]`.
  """
  @spec match_path?(String.t(), [String.t()]) :: boolean()
  def match_path?(path, split_path) when is_binary(path) and is_list(split_path) do
    pattern_segments =
      path
      |> String.trim_leading("/")
      |> String.split("/", trim: true)

    match_segments?(pattern_segments, split_path)
  end

  defp match_segments?([], []), do: true

  defp match_segments?([":" <> _param | pattern_rest], [_actual | actual_rest]),
    do: match_segments?(pattern_rest, actual_rest)

  defp match_segments?([segment | pattern_rest], [segment | actual_rest]),
    do: match_segments?(pattern_rest, actual_rest)

  defp match_segments?(_pattern, _actual), do: false
end
