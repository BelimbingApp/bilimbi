defmodule Bilimbi.Domain.HookFixture.Web.Clash do
  use Phoenix.Component

  def first(assigns) do
    ~H"""
    <p id="first-clash" phx-hook=".Duplicate">First</p>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Duplicate">
      export default {mounted() { this.el.textContent = "first" }}
    </script>
    """
  end

  def second(assigns) do
    ~H"""
    <p id="second-clash" phx-hook=".Duplicate">Second</p>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Duplicate">
      export default {mounted() { this.el.textContent = "second" }}
    </script>
    """
  end
end
