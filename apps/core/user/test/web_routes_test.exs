defmodule Bilimbi.Core.User.WebRoutesTest do
  use ExUnit.Case, async: true

  defp routes do
    {routes, _binding} = Code.eval_file(Path.expand("../priv/web_routes.exs", __DIR__))
    routes
  end

  # Embed contributions share the manifest with routes and carry no :path.
  defp route!(path), do: Enum.find(routes(), &(&1[:path] == path))

  test "retains the capability-gated create, show, and edit routes" do
    assert %{
             live: Bilimbi.Core.User.Web.FormLive,
             session: :auth,
             capability: "admin.user.create"
           } = route!("/users/new")

    assert %{
             live: Bilimbi.Core.User.Web.ShowLive,
             session: :auth,
             capability: "admin.user.view"
           } = route!("/users/:id")

    assert %{
             live: Bilimbi.Core.User.Web.FormLive,
             session: :auth,
             capability: "admin.user.update"
           } = route!("/users/:id/edit")
  end

  test "every administrative route carries a capability" do
    # The previous form of this test pinned the whole list, so adding any route
    # failed it and the fix was to paste the new entry in. That checks the list
    # has not changed rather than that the rules hold. This states the rule: an
    # admin route without a capability is reachable by any signed-in account.
    for route <- routes(),
        is_binary(route[:path]) and String.starts_with?(route[:path], "/users") do
      assert is_binary(route[:capability]),
             "#{route[:path]} is an administrative route with no capability"
    end
  end

  test "contributes the employee account panel as a discovered embed" do
    assert %{
             embed: "employee.accounts",
             live_component: Bilimbi.Core.User.Web.EmployeeAccountPanel,
             operation_handler: Bilimbi.Core.User.Web.EmployeeAccountPanel
           } in routes()
  end

  test "the profile route is deliberately open to any signed-in account" do
    # Not an oversight: Belimbing guards `settings/profile` with authentication
    # alone, because it is the actor's own account. Asserted so that adding a
    # capability here is a decision someone has to argue for, and removing one
    # elsewhere still fails the test above.
    assert %{live: Bilimbi.Core.User.Web.ProfileLive, session: :auth} =
             profile = route!("/settings/profile")

    refute Map.has_key?(profile, :capability)
  end
end
