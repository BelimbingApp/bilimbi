defmodule BilimbiWeb.Layouts do
  @moduledoc false

  defdelegate auth(assigns), to: Bilimbi.Base.UI.Layouts
  defdelegate app(assigns), to: Bilimbi.Base.UI.Layouts
  defdelegate flash_group(assigns), to: Bilimbi.Base.UI.Layouts
  def root(assigns), do: Bilimbi.Base.UI.Layouts.root(assigns)
end
