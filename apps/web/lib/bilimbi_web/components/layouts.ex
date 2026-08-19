defmodule BilimbiWeb.Layouts do
  @moduledoc false

  use Phoenix.Component

  defdelegate auth(assigns), to: Bilimbi.Base.UI.Layouts
  defdelegate flash_group(assigns), to: Bilimbi.Base.UI.Layouts
  def root(assigns), do: Bilimbi.Base.UI.Layouts.root(assigns)

  attr(:flash, :map, required: true)
  attr(:current_scope, :map, required: true)
  attr(:active_nav, :any, required: true)
  slot(:inner_block, required: true)

  def app(assigns) do
    ~H"""
    <Bilimbi.Base.UI.Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_nav={@active_nav}
    >
      <:topbar_actions>
        <.live_component
          module={Bilimbi.Core.User.Web.NotificationBellComponent}
          id="topbar-notification-bell"
          current_scope={@current_scope}
        />
      </:topbar_actions>
      {render_slot(@inner_block)}
    </Bilimbi.Base.UI.Layouts.app>
    """
  end
end
