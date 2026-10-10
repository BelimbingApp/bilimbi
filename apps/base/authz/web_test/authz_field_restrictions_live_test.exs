defmodule BilimbiWeb.AuthzFieldRestrictionsLiveTest do
  @moduledoc """
  Administration › Authorization › Field Restrictions: an operator restricts
  catalog fields for roles from a dialog, changes the roles of one, and
  lifts the restriction. Rows are created through
  `Authz.put_field_restrictions/3`, so what is under test is what the
  platform stores, and what the dialog offers is the installed catalog minus
  the protected fields.
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
    conn |> log_in_as() |> live(~p"/authz/field-restrictions")
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
    view |> form("#field-restrictions-form", %{"restriction" => tables}) |> render_change()
    view |> form("#field-restrictions-form", %{"restriction" => params}) |> render_change()
    view
  end

  defp option(id), do: "label[for='#{id}']"

  defp open_dialog(view) do
    view |> element("#field-restrictions-new") |> render_click()
    assert has_element?(view, "#field-restrictions-dialog")
    view
  end

  test "requires authentication and the capability", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/field-restrictions")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/authz/field-restrictions")
  end

  test "lists nothing restricted, keeps the dialog closed until asked, and marks its nav row",
       %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(
             view,
             "#field-restrictions-empty",
             "No field is restricted in this tenant"
           )

    assert has_element?(view, "#nav-admin-authz-field-restrictions[aria-current='page']")
    assert has_element?(view, "#nav-admin-authz-field-restrictions", "Field Restrictions")
    refute has_element?(view, "#field-restrictions-dialog")
  end

  test "the dialog asks roles first, then tables, then the fields of the chosen tables, without protected fields",
       %{conn: conn, operator: operator} do
    finance = role!(operator, "Finance", "finance")
    {:ok, view, _html} = open(conn)
    open_dialog(view)

    html = render(view)
    roles_at = :binary.match(html, "id=\"field-restrictions-roles\"") |> elem(0)
    tables_at = :binary.match(html, "id=\"field-restrictions-tables\"") |> elem(0)
    fields_at = :binary.match(html, "id=\"field-restrictions-fields\"") |> elem(0)
    assert roles_at < tables_at and tables_at < fields_at

    assert has_element?(
             view,
             "#field-restrictions-roles-label",
             "Choose the roles to restrict field access"
           )

    assert has_element?(view, "#field-restrictions-roles-option-#{finance.id}")
    assert has_element?(view, "#field-restrictions-tables-option-companies")
    assert has_element?(view, "#field-restrictions-fields[disabled]")
    refute has_element?(view, "#field-restrictions-outcome")
    assert has_element?(view, "#field-restrictions-save[disabled]")

    view
    |> form("#field-restrictions-form", %{"restriction" => %{"table_ids" => ["companies"]}})
    |> render_change()

    assert has_element?(view, "#field-restrictions-tables-chip-companies", "Companies")
    assert has_element?(view, "#field-restrictions-fields-option-companies\\.email")
    assert has_element?(view, "#field-restrictions-fields-option-companies\\.tax_id")
    refute has_element?(view, "#field-restrictions-fields-option-companies\\.code")
    refute has_element?(view, "#field-restrictions-fields-option-companies\\.name")
    refute has_element?(view, "#field-restrictions-fields-option-companies\\.id")
    refute has_element?(view, "#field-restrictions-fields-option-companies\\.parent_id")

    # Escape and Cancel are the same action: the dialog closes and nothing is written.
    view |> element("#field-restrictions-cancel") |> render_click()
    refute has_element?(view, "#field-restrictions-dialog")
    assert {:ok, []} = Authz.list_field_restrictions(operator)
  end

  test "restricts two fields for a role in one go, changes the roles of one, and removes it", %{
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

    assert has_element?(view, "#field-restrictions-roles-chip-#{finance.id}", "Finance")
    assert has_element?(view, "#field-restrictions-fields-chip-companies\\.email", "Email")

    assert has_element?(
             view,
             "#field-restrictions-outcome",
             "Finance will read Companies › Tax ID and Companies › Email as Restricted. Every other role sees the value."
           )

    assert has_element?(view, "#field-restrictions-save", "Restrict 2 fields")
    refute has_element?(view, "#field-restrictions-save[disabled]")

    view |> form("#field-restrictions-form") |> render_submit()

    refute has_element?(view, "#field-restrictions-dialog")
    assert has_element?(view, "#flash-success", "2 fields are restricted for Finance.")
    assert has_element?(view, "#field-restrictions", "Email")
    assert has_element?(view, "#field-restrictions", "Tax ID")
    assert has_element?(view, "#field-restrictions", "Finance")

    {:ok, [email, tax_id]} = Authz.list_field_restrictions(operator)
    assert {email.field_id, email.role_ids} == {"email", [finance.id]}
    assert {tax_id.field_id, tax_id.role_ids} == {"tax_id", [finance.id]}

    # Editing opens the smaller dialog on that row and replaces its roles.
    view |> element("#field-restriction-#{email.id}-edit") |> render_click()
    assert has_element?(view, "#field-restrictions-dialog-title", "Restrict Companies › Email")
    refute has_element?(view, "#field-restrictions-tables")
    assert has_element?(view, "#field-restrictions-roles-chip-#{finance.id}", "Finance")

    view
    |> form("#field-restrictions-form", %{
      "restriction" => %{
        "role_ids" => [Integer.to_string(finance.id), Integer.to_string(legal.id)]
      }
    })
    |> render_submit()

    refute has_element?(view, "#field-restrictions-dialog")

    assert has_element?(
             view,
             "#flash-success",
             "Companies › Email is restricted for Finance and Legal."
           )

    assert has_element?(view, "#field-restrictions", "Legal")
    {:ok, [email, _tax_id]} = Authz.list_field_restrictions(operator)
    assert Enum.sort(email.role_ids) == Enum.sort([finance.id, legal.id])

    # Removing confirms through the shared dialog.
    view |> element("#field-restriction-#{email.id}-remove") |> render_click()
    assert has_element?(view, "#field-restrictions-remove-confirm", "visible to every role again")

    view
    |> element("#field-restrictions-remove-confirm button", "Remove restriction")
    |> render_click()

    assert has_element?(view, "#flash-success", "Companies › Email is no longer restricted.")
    assert {:ok, [%{field_id: "tax_id"}]} = Authz.list_field_restrictions(operator)
  end

  test "a chip's remove button drops that pick, and dropping a table drops its fields", %{
    conn: conn,
    operator: operator
  } do
    finance = role!(operator, "Finance", "finance")
    {:ok, view, _html} = open(conn)
    open_dialog(view)

    pick(view, %{
      "role_ids" => [Integer.to_string(finance.id)],
      "table_ids" => ["companies"],
      "field_keys" => ["companies.email"]
    })

    view |> element("#field-restrictions-fields-chip-companies\\.email-remove") |> render_click()
    refute has_element?(view, "#field-restrictions-fields-chip-companies\\.email")
    assert has_element?(view, "#field-restrictions-save[disabled]")

    pick(view, %{"table_ids" => ["companies"], "field_keys" => ["companies.email"]})
    assert has_element?(view, "#field-restrictions-fields-chip-companies\\.email")

    view |> element("#field-restrictions-tables-chip-companies-remove") |> render_click()
    refute has_element?(view, "#field-restrictions-tables-chip-companies")
    refute has_element?(view, "#field-restrictions-fields-chip-companies\\.email")
    assert has_element?(view, "#field-restrictions-fields[disabled]")

    view |> element("#field-restrictions-roles-chip-#{finance.id}-remove") |> render_click()
    refute has_element?(view, "#field-restrictions-roles-chip-#{finance.id}")
    assert {:ok, []} = Authz.list_field_restrictions(operator)
  end

  test "fields of several tables are offered with their table named", %{conn: conn} do
    {:ok, view, _html} = open(conn)
    open_dialog(view)

    tables =
      Authz.field_restriction_catalog()
      |> Enum.map(& &1.id)
      |> Enum.take(2)

    view
    |> form("#field-restrictions-form", %{"restriction" => %{"table_ids" => tables}})
    |> render_change()

    case tables do
      [_one, _two] ->
        assert has_element?(
                 view,
                 option("field-restrictions-fields-option-companies.email"),
                 "Companies › Email"
               )

      [_one] ->
        assert has_element?(
                 view,
                 option("field-restrictions-fields-option-companies.email"),
                 "Email"
               )
    end
  end

  test "nothing is saved without a role or without a field", %{conn: conn, operator: operator} do
    finance = role!(operator, "Finance", "finance")
    {:ok, view, _html} = open(conn)
    open_dialog(view)

    # Fields without a role: the button stays disabled, and a forced submit
    # is refused by the domain.
    pick(view, %{"table_ids" => ["companies"], "field_keys" => ["companies.tax_id"]})
    refute has_element?(view, "#field-restrictions-outcome")
    assert has_element?(view, "#field-restrictions-save[disabled]")

    render_submit(view, "save", %{
      "restriction" => %{"table_ids" => ["companies"], "field_keys" => ["companies.tax_id"]}
    })

    assert has_element?(view, "#field-restrictions-dialog")

    assert has_element?(
             view,
             "#field-restrictions-dialog-flash-error",
             "The restriction could not be saved."
           )

    # A field whose table was dropped is not a pick: a replayed form with the
    # field but not its table saves nothing.
    render_submit(view, "save", %{
      "restriction" => %{
        "role_ids" => [Integer.to_string(finance.id)],
        "table_ids" => [],
        "field_keys" => ["companies.tax_id"]
      }
    })

    assert has_element?(view, "#field-restrictions-dialog")

    assert has_element?(
             view,
             "#field-restrictions-dialog-flash-error",
             "The restriction could not be saved."
           )

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
             view |> element("#field-restrictions-new") |> render_click()

    grant_capabilities!(@manage)
    assert {:ok, []} = Authz.list_field_restrictions(Authentication.sign_in(scope, 91, 73))
  end
end
