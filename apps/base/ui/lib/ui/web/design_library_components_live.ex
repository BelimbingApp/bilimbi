defmodule Bilimbi.Base.UI.Web.DesignLibraryComponentsLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.UI.Web.DesignLibraryLive

  @impl true
  def mount(_params, _session, socket), do: DesignLibraryLive.mount_area(:components, socket)

  @impl true
  def handle_event(event, params, socket),
    do: DesignLibraryLive.handle_event(event, params, socket)

  @impl true
  def render(assigns), do: DesignLibraryLive.render(assigns)
end
