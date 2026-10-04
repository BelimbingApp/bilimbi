defmodule Bilimbi.Core.Employee.WebRoutesEmbedTest do
  use ExUnit.Case, async: true

  test "declares the company-employees panel as a module-owned discovered embed" do
    embeds = Enum.filter(routes(), &Map.has_key?(&1, :embed))

    assert %{
             embed: "company.employees",
             live_component: Bilimbi.Core.Employee.Web.CompanyEmployeesPanel
           } in embeds
  end

  defp routes do
    path = Path.expand("../priv/web_routes.exs", __DIR__)
    {routes, _binding} = Code.eval_file(path)
    routes
  end
end
