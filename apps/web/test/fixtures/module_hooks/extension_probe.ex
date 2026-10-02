defmodule Bilimbi.Extension.HookFixture.Web.Probe do
  @moduledoc false

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <p id="extension-hook-probe" phx-hook=".Probe">Waiting</p>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Probe">
      export default {mounted() { this.el.dataset.extensionHook = "mounted" }}
    </script>
    """
  end
end
