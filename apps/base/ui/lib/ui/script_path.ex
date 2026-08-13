defmodule Bilimbi.Base.UI.ScriptPath do
  @moduledoc false

  # Phoenix.VerifiedRoutes still calls `endpoint.path/1` and
  # `endpoint.static_path/1` when generating `~p` strings. This module is a
  # script-name-empty stand-in so `base/ui` never depends on BilimbiWeb.Endpoint.

  def path(path) when is_binary(path), do: path
  def static_path(path) when is_binary(path), do: path
end
