defmodule Bilimbi.Core.Address.WebRoutesTest do
  use ExUnit.Case, async: true

  test "declares the capability-gated module-owned Address routes" do
    {routes, _binding} =
      Code.eval_file(Path.expand("../priv/web_routes.exs", __DIR__))

    assert routes == [
             %{
               path: "/addresses",
               live: Bilimbi.Core.Address.Web.IndexLive,
               session: :auth,
               capability: "admin.address.list"
             },
             %{
               path: "/addresses/create",
               live: Bilimbi.Core.Address.Web.CreateLive,
               session: :auth,
               capability: "admin.address.create"
             },
             %{
               path: "/addresses/:id",
               live: Bilimbi.Core.Address.Web.ShowLive,
               session: :auth,
               capability: "admin.address.view"
             },
             %{
               embed: "employee.addresses",
               live_component: Bilimbi.Core.Address.Web.EmployeeAddressesPanel
             }
           ]
  end
end
