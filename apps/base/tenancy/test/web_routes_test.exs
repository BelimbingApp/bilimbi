defmodule Bilimbi.Base.Tenancy.WebRoutesTest do
  use ExUnit.Case, async: true

  test "web_routes.exs evaluates to the tenants admin route" do
    path = Path.expand("../priv/web_routes.exs", __DIR__)
    {routes, _} = Code.eval_file(path)

    assert [
             %{
               path: "/tenancy/tenants",
               live: Bilimbi.Base.Tenancy.Web.TenantsLive,
               session: :auth,
               capability: "admin.tenancy.tenant.list"
             }
           ] = routes
  end

  test "TenantsLive is a compiled LiveView" do
    assert {:module, Bilimbi.Base.Tenancy.Web.TenantsLive} =
             Code.ensure_loaded(Bilimbi.Base.Tenancy.Web.TenantsLive)

    assert function_exported?(Bilimbi.Base.Tenancy.Web.TenantsLive, :__live__, 0)
  end
end
