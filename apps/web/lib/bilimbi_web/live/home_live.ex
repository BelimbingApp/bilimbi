defmodule BilimbiWeb.HomeLive do
  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Company

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Platform baseline")
     |> assign(:current_scope, nil)
     |> assign_company(Company.platform_operator_company())}
  end

  defp assign_company(socket, {:ok, company}) do
    socket
    |> assign(:company_state, :ready)
    |> assign(:platform_operator_company, company)
  end

  defp assign_company(socket, {:error, state}) do
    socket
    |> assign(:company_state, state)
    |> assign(:platform_operator_company, nil)
  end
end
