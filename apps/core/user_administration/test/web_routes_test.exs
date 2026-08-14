defmodule Bilimbi.Core.UserAdministration.WebRoutesTest do
  use ExUnit.Case, async: true

  test "owns exactly the capability-gated Users index route" do
    {routes, _binding} =
      Code.eval_file(Path.expand("../priv/web_routes.exs", __DIR__))

    assert routes == [
             %{
               path: "/users",
               live: Bilimbi.Core.UserAdministration.Web.IndexLive,
               session: :auth,
               capability: "admin.user.list"
             }
           ]
  end
end
