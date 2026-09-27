defmodule Bilimbi.Base.Grid.Web.GridLive do
  @moduledoc false
  use Bilimbi.Base.UI, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Grid"), active_nav: "grid")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="grid-page" variant={:list}>
        <.header>{gettext("Grid")}</.header>
      </.page>
    </Layouts.app>
    """
  end
end
