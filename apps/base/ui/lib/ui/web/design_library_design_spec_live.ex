defmodule Bilimbi.Base.UI.Web.DesignLibraryDesignSpecLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.UI.Web.DesignLibraryLive

  @impl true
  def mount(_params, _session, socket), do: DesignLibraryLive.mount_area(:design_spec, socket)

  @impl true
  def render(assigns), do: DesignLibraryLive.render(assigns)
end
