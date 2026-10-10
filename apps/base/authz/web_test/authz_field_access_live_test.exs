defmodule BilimbiWeb.AuthzFieldAccessLiveTest do
  @moduledoc """
  Administration › Authorization › Field Access: an operator restricts
  catalog fields to roles from a dialog, changes who sees one, and lifts the
  restriction. Rows are created through `Authz.put_field_restrictions/3`, so
  what is under test is what the platform stores, and what the dialog offers
  is the installed catalog minus the protected fields.
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

  # A browser offers the fields only once a table is chosen, and
  # `Phoenix.LiveViewTest` checks every value against the rendered boxes, so
  # a pick goes in two changes: the tables, then the fields and roles.
  defp pick(view, params) do
    tables = Map.take(params, ["table_ids"])
    view |> form("#field-access-form", %{"restriction" => tables}) |> render_change()
    view |> form("#field-access-form", %{"restriction" => params}) |> render_change()
    view
  end

  defp option(id), do: "label[for='#{id}']"

  defp open_dialog(view) do
    view |> element("#field-access-new") |> render_click()
    assert has_element?(view, "#field-access-dialog")
    view
  end

  test "requires authentication and the capability", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/field-access")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/authz/field-access")
  end

  test "lists nothing restricted, keeps the dialog closed until asked, and marks its nav row",
       %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(
             view,
             "#field-restrictions-empty",
             "No field is restricted in this tenant"
           )

    assert has_element?(view, "#nav-admin-authz-field-access[aria-current='page']")
    refute has_element?(view, "#field-access-dialog")
  end

  test "the dialog asks roles first, then tables, then the fields of the chosen tables, without protected fields",
       %{conn: conn, operator: operator} do
    finance = role!(operator, "Finance", "finance")
    {:ok, view, _html} = open(conn)
    open_dialog(view)

    html = render(view)
    roles_at = :binary.match(html, "id=\"field-access-roles\"") |> elem(0)
    tables_at = :binary.match(html, "id=\"field-access-tables\"") |> elem(0)
    fields_at = :binary.match(html, "id=\"field-access-fields\"") |> elem(0)
    assert roles_at < tables_at and tables_at < fields_at

    assert has_element?(view, "#field-access-roles-option-#{finance.id}")
    assert has_element?(view, "#field-access-tables-option-companies")
    assert has_element?(view, "#field-access-fields[disabled]")
    assert has_element?(view, "#field-access-outcome", "Choose at least one field")
    assert has_element?(view, "#field-access-save[disabled]")

    view
    |> form("#field-access-form", %{"restriction" => %{"table_ids" => ["companies"]}})
    |> render_change()

    assert has_element?(view, "#field-access-fields-option-companies\\.email")
    assert has_element?(view, "#field-access-fields-option-companies\\.tax_id")
    refute has_element?(view, "#field-access-fields-option-companies\\.code")
    refute has_element?(view, "#field-access-fields-option-companies\\.name")
    refute has_element?(view, "#field-access-fields-option-companies\\.id")
    refute has_element?(view, "#field-access-fields-option-companies\\.parent_id")

    # Escape and Cancel are the same action: the dialog closes and nothing is written.
    view |> element("#field-access-cancel") |> render_click()
    refute has_element?(view, "#field-access-dialog")
    assert {:ok, []} = Authz.list_field_restrictions(operator)
  end

  test "restricts two fields to a role in one go, changes the roles of one, and removes it", %{
    conn: conn,
    operator: operator
  } do
    finance = role!(operator, "Finance", "finance")
    legal = role!(operator, "Legal", "legal")

    {:ok, view, _html} = open(conn)
    open_dialog(view)

    pick(view, %{
      "role_ids" => [Integer.to_string(finance.id)],
      "table_ids" => ["companies"],
      "field_keys" => ["companies.email", "companies.tax_id"]
    })

    assert has_element?(
             view,
             "#field-access-outcome",
             "Companies › Tax ID and Companies › Email will stay visible to Finance and read Restricted for every other role."
           )

    assert has_element?(view, "#field-access-save", "Restrict 2 fields")

    view |> form("#field-access-form") |> render_submit()

    refute has_element?(view, "#field-access-dialog")
    assert has_element?(view, "#flash-success", "2 fields stay visible to Finance only.")
    assert has_element?(view, "#field-restrictions", "Email")
    assert has_element?(view, "#field-restrictions", "Tax ID")
    assert has_element?(view, "#field-restrictions", "Finance")

    {:ok, [email, tax_id]} = Authz.list_field_restrictions(operator)
    assert {email.field_id, email.role_ids} == {"email", [finance.id]}
    assert {tax_id.field_id, tax_id.role_ids} == {"tax_id", [finance.id]}

    # Editing opens the smaller dialog on that row and replaces its roles.
    view |> element("#field-restriction-#{email.id}-edit") |> render_click()
    assert has_element?(view, "#field-access-dialog-title", "Who may see Companies › Email")
    refute has_element?(view, "#field-access-tables")
    assert has_element?(view, "#field-access-roles-option-#{finance.id}[checked]")

    view
    |> form("#field-access-form", %{
      "restriction" => %{
        "role_ids" => [Integer.to_string(finance.id), Integer.to_string(legal.id)]
      }
    })
    |> render_submit()

    refute has_element?(view, "#field-access-dialog")

    assert has_element?(
             view,
             "#flash-success",
             "Companies › Email stays visible to Finance and Legal only."
           )

    assert has_element?(view, "#field-restrictions", "Legal")
    {:ok, [email, _tax_id]} = Authz.list_field_restrictions(operator)
    assert Enum.sort(email.role_ids) == Enum.sort([finance.id, legal.id])

    # Removing confirms through the shared dialog.
    view |> element("#field-restriction-#{email.id}-remove") |> render_click()
    assert has_element?(view, "#field-access-remove-confirm", "visible to every role again")
    view |> element("#field-access-remove-confirm button", "Remove restriction") |> render_click()

    assert has_element?(view, "#flash-success", "Companies › Email is no longer restricted.")
    assert {:ok, [%{field_id: "tax_id"}]} = Authz.list_field_restrictions(operator)
  end

  test "fields of several tables are offered with their table named", %{conn: conn} do
    {:ok, view, _html} = open(conn)
    open_dialog(view)

    tables =
      Authz.field_restriction_catalog()
      |> Enum.map(& &1.id)
      |> Enum.take(2)

    view
    |> form("#field-access-form", %{"restriction" => %{"table_ids" => tables}})
    |> render_change()

    case tables do
      [_one, _two] ->
        assert has_element?(
                 view,
                 option("field-access-fields-option-companies.email"),
                 "Companies › Email"
               )

      [_one] ->
        assert has_element?(view, option("field-access-fields-option-companies.email"), "Email")
    end
  end

  test "a restriction with no role hides the field from everyone, and says so before saving", %{
    conn: conn,
    operator: operator
  } do
    {:ok, view, _html} = open(conn)
    open_dialog(view)

    pick(view, %{"table_ids" => ["companies"], "field_keys" => ["companies.tax_id"]})

    assert has_element?(
             view,
             "#field-access-outcome",
             "Companies › Tax ID will read Restricted for every role, including yours"
           )

    view |> form("#field-access-form") |> render_submit()

    assert has_element?(
             view,
             "#flash-success",
             "Companies › Tax ID reads Restricted for every role."
           )

    assert has_element?(view, "#field-restrictions", "No role")
    assert {:ok, [%{role_ids: []}]} = Authz.list_field_restrictions(operator)
  end

  test "a field whose table was dropped is not restricted", %{conn: conn, operator: operator} do
    {:ok, view, _html} = open(conn)
    open_dialog(view)

    # The browser cannot send this, but a replayed form could: the field's
    # table is no longer chosen, so the pick is dropped and nothing is saved.
    render_submit(view, "save", %{
      "restriction" => %{"table_ids" => [], "field_keys" => ["companies.tax_id"]}
    })

    assert has_element?(view, "#field-access-dialog")
    assert has_element?(view, "#field-access-dialog-flash-error", "Choose at least one field")
    assert {:ok, []} = Authz.list_field_restrictions(operator)
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
             view |> element("#field-access-new") |> render_click()

    grant_capabilities!(@manage)
    assert {:ok, []} = Authz.list_field_restrictions(Authentication.sign_in(scope, 91, 73))
  end
end
