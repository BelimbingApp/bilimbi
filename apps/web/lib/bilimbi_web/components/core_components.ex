defmodule BilimbiWeb.CoreComponents do
  @moduledoc """
  Compatibility import surface for shared UI components.

  New code should import `Bilimbi.Base.UI.Components` directly.
  """

  alias Phoenix.LiveView.JS

  defdelegate flash(assigns), to: Bilimbi.Base.UI.Components
  defdelegate alert(assigns), to: Bilimbi.Base.UI.Components
  defdelegate badge(assigns), to: Bilimbi.Base.UI.Components
  defdelegate button(assigns), to: Bilimbi.Base.UI.Components
  defdelegate input(assigns), to: Bilimbi.Base.UI.Components
  defdelegate header(assigns), to: Bilimbi.Base.UI.Components
  defdelegate table(assigns), to: Bilimbi.Base.UI.Components
  defdelegate list(assigns), to: Bilimbi.Base.UI.Components
  defdelegate icon(assigns), to: Bilimbi.Base.UI.Components

  defdelegate show(js \\ %JS{}, selector), to: Bilimbi.Base.UI.Components
  defdelegate hide(js \\ %JS{}, selector), to: Bilimbi.Base.UI.Components

  defdelegate translate_error(arg), to: Bilimbi.Base.UI.Components
  defdelegate translate_errors(errors, field), to: Bilimbi.Base.UI.Components
end
