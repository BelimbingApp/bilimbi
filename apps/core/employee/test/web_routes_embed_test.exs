defmodule Bilimbi.Core.Employee.WebRoutesEmbedTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Core.Employee.Web.Router

  test "declares the company-employees panel as a module-owned discovered embed" do
    embeds = Enum.filter(Router.routes(), &Map.has_key?(&1, :embed))

    assert %{
             embed: "company.employees",
             live_component: Bilimbi.Core.Employee.Web.CompanyEmployeesPanel
           } in embeds
  end
end
