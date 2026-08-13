defmodule Bilimbi.Base.Session.WebRoutesTest do
  use ExUnit.Case, async: true

  test "web_routes.exs evaluates to the sessions admin route" do
    path = Path.expand("../priv/web_routes.exs", __DIR__)
    {routes, _} = Code.eval_file(path)

    assert [
             %{
               path: "/system/sessions",
               live: Bilimbi.Base.Session.Web.IndexLive,
               session: :auth,
               capability: "admin.system.session.list"
             }
           ] = routes
  end

  test "IndexLive is a compiled LiveView" do
    assert {:module, Bilimbi.Base.Session.Web.IndexLive} =
             Code.ensure_loaded(Bilimbi.Base.Session.Web.IndexLive)

    assert function_exported?(Bilimbi.Base.Session.Web.IndexLive, :__live__, 0)
  end
end
