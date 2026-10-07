defmodule BilimbiWeb.AuthzFieldAccessLiveTest do
  @moduledoc """
  Administration › Authorization › Field Access: an operator restricts a
  catalog field to roles, changes who sees it, and lifts the restriction.
  Rows are created through `Authz.put_field_restriction/4`, so what is under
  test is what the platform stores, and what the picker offers is the
  installed catalog minus the protected fields.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication

  @manage "admin.authz.field.manage"

  setup do
    signed_in_identity!()
    {:ok, scope} = Tenancy.scope(41)
    operator = Authentication.sign_in(scope, 91, 73)
    %{scope: scope, operator: operator}
  end

  defp open(conn) do
    grant_capabilities!(@manage)
    conn |> log_in_as() |> live(~p"/authz/field-access")
  end

  defp role!(operator, name, code) do
    {:ok, role} = Authz.create_role(operator, 73, %{name: name, code: code})
    role
  end

  test "requires authentication and the capability", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/field-access")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/authz/field-access")
  end

  test "lists nothing restricted, offers the catalog without protected fields, and marks its nav row",
       %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(
             view,
             "#field-restrictions-empty",
             "No field is restricted in this tenant"
           )

    assert has_element?(view, "#nav-admin-authz-field-access[aria-current='page']")
    assert has_element?(view, "#field-access-table option[value='companies']", "Companies")

    view
    |> form("#field-access-form", %{"restriction" => %{"table_id" => "companies"}})
    |> render_change()

    assert has_element?(view, "#field-access-field option[value='email']", "Email")
    assert has_element?(view, "#field-access-field option[value='tax_id']", "Tax ID")
    refute has_element?(view, "#field-access-field option[value='code']")
    refute has_element?(view, "#field-access-field option[value='name']")
    refute has_element?(view, "#field-access-field option[value='id']")
    refute has_element?(view, "#field-access-field option[value='parent_id']")
  end

  test "restricts a field to roles, changes the roles, and removes the restriction", %{
    conn: conn,
    operator: operator
  } do
    finance = role!(operator, "Finance", "finance")
    legal = role!(operator, "Legal", "legal")

    {:ok, view, _html} = open(conn)

    view
    |> form("#field-access-form", %{"restriction" => %{"table_id" => "companies"}})
    |> render_change()

    view
    |> form("#field-access-form", %{
      "restriction" => %{
        "table_id" => "companies",
        "field_id" => "email",
        "role_ids" => [Integer.to_string(finance.id)]
      }
    })
    |> render_submit()

    assert has_element?(view, "#flash-success", "Companies › Email is restricted to Finance.")
    assert has_element?(view, "#field-restrictions", "Companies")
    assert has_element?(view, "#field-restrictions", "Email")
    assert has_element?(view, "#field-restrictions", "Finance")

    {:ok, [restriction]} = Authz.list_field_restrictions(operator)
    assert restriction.role_ids == [finance.id]

    # Editing loads the row into the form and replaces its roles.
    view |> element("#field-restriction-#{restriction.id}-edit") |> render_click()
    assert has_element?(view, "#field-access-form-heading", "Change who sees this field")
    assert has_element?(view, "#field-access-table[disabled]")

    view
    |> form("#field-access-form", %{
      "restriction" => %{
        "role_ids" => [Integer.to_string(finance.id), Integer.to_string(legal.id)]
      }
    })
    |> render_submit()

    assert has_element?(view, "#field-restrictions", "Legal")
    {:ok, [restriction]} = Authz.list_field_restrictions(operator)
    assert Enum.sort(restriction.role_ids) == Enum.sort([finance.id, legal.id])

    # Removing confirms through the shared dialog.
    view |> element("#field-restriction-#{restriction.id}-remove") |> render_click()
    assert has_element?(view, "#field-access-remove-confirm", "visible to every role again")
    view |> element("#field-access-remove-confirm button", "Remove restriction") |> render_click()

    assert has_element?(view, "#flash-success", "Companies › Email is no longer restricted.")
    assert has_element?(view, "#field-restrictions-empty")
    assert {:ok, []} = Authz.list_field_restrictions(operator)
  end

  test "a restriction with no role hides the field from everyone", %{
    conn: conn,
    operator: operator
  } do
    {:ok, view, _html} = open(conn)

    view
    |> form("#field-access-form", %{"restriction" => %{"table_id" => "companies"}})
    |> render_change()

    view
    |> form("#field-access-form", %{
      "restriction" => %{"table_id" => "companies", "field_id" => "tax_id"}
    })
    |> render_submit()

    assert has_element?(view, "#flash-success", "Companies › Tax ID is restricted to no role.")
    assert has_element?(view, "#field-restrictions", "No role")
    assert {:ok, [%{role_ids: []}]} = Authz.list_field_restrictions(operator)
  end

  test "once the capability is revoked the page sends the operator away and writes nothing", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = open(conn)
    revoke_capability!(scope, @manage)

    # The route is gated on the same capability, so the host refuses the
    # next event and leaves the page.
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             view
             |> form("#field-access-form", %{"restriction" => %{"table_id" => "companies"}})
             |> render_change()

    grant_capabilities!(@manage)
    assert {:ok, []} = Authz.list_field_restrictions(Authentication.sign_in(scope, 91, 73))
  end
end
