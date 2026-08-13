defmodule Bilimbi.Core.User.WebRoutesTest do
  use ExUnit.Case, async: true

  test "declares the four capability-gated module-owned user routes" do
    {routes, _binding} =
      Code.eval_file(Path.expand("../priv/web_routes.exs", __DIR__))

    assert routes == [
             %{
               path: "/users",
               live: Bilimbi.Core.User.Web.IndexLive,
               session: :auth,
               capability: "admin.user.list"
             },
             %{
               path: "/users/new",
               live: Bilimbi.Core.User.Web.FormLive,
               session: :auth,
               capability: "admin.user.create"
             },
             %{
               path: "/users/:id",
               live: Bilimbi.Core.User.Web.ShowLive,
               session: :auth,
               capability: "admin.user.view"
             },
             %{
               path: "/users/:id/edit",
               live: Bilimbi.Core.User.Web.FormLive,
               session: :auth,
               capability: "admin.user.update"
             }
           ]
  end
end
