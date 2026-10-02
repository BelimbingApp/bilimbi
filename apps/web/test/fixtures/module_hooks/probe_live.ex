defmodule Bilimbi.Domain.HookFixture.Web.ProbeLive do
  use Bilimbi.Base.UI, :live_view

  def mount(_params, _session, socket), do: {:ok, socket}

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <p id="module-hook-probe" phx-hook=".Probe">Waiting for browser hook</p>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Probe">
        export default {
          mounted() {
            this.el.textContent = "Mounted module hook ran"
            this.el.dataset.moduleHook = "mounted"
          }
        }
      </script>
    </Layouts.auth>
    """
  end
end
