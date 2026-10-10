defmodule BilimbiWeb.AuthzPrincipalPagesRetiredTest do
  @moduledoc """
  The Principal Roles and Principal Capabilities listings are retired.

  Every role assignment and direct grant is made on the person, in the access
  section of `/users/:id`, and who holds a role is read on that role's page.
  Authorization keeps Capabilities, Roles, Decision Logs and Field Access.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    signed_in_identity!()
    :ok
  end

  test "the two listings answer with a plain 404", %{conn: conn} do
    grant_capabilities!(["admin.authz.role.list", "admin.authz.capability.list"])

    for retired <- ["/authz/principal-roles", "/authz/principal-capabilities"] do
      assert Phoenix.Router.route_info(BilimbiWeb.Router, "GET", retired, "localhost") == :error
      assert conn |> log_in_as() |> get(retired) |> Map.fetch!(:status) == 404
    end
  end

  test "the Authorization menu keeps its four screens and no principal listing", %{conn: conn} do
    grant_capabilities!([
      "admin.authz.capability.list",
      "admin.authz.role.list",
      "admin.authz.decision-log.list",
      "admin.authz.field.manage"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/authz/roles")

    assert has_element?(view, "#nav-admin-authz-capability")
    assert has_element?(view, "#nav-admin-authz-role[aria-current='page']")
    assert has_element?(view, "#nav-admin-authz-decision-log")
    assert has_element?(view, "#nav-admin-authz-field-access")
    refute has_element?(view, "#nav-admin-authz-principal-role")
    refute has_element?(view, "#nav-admin-authz-principal-capability")
    refute has_element?(view, "#app-shell a[href='/authz/principal-roles']")
    refute has_element?(view, "#app-shell a[href='/authz/principal-capabilities']")
  end
end
