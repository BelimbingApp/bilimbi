defmodule BilimbiWeb.AuthzRolesLiveTest do
  @moduledoc """
  Roles list and detail.

  The assertion that matters most here is the tenancy boundary. `Authz` owns
  the rule; these prove the screens inherit it rather than quietly widening
  it, because a leak would look like a perfectly ordinary list.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    {:ok, ours} = Tenancy.scope(41)
    {:ok, theirs} = Tenancy.scope(42)
    %{ours: ours, theirs: theirs}
  end

  defp patched_params(view) do
    assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end

  defp open_index(conn) do
    grant_capabilities!("admin.authz.role.list")
    conn |> log_in_as() |> live(~p"/authz/roles")
  end

  describe "index" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/roles")
    end

    test "redirects away without admin.authz.role.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/authz/roles")
    end

    test "offers Create Role only to an actor holding the capability", %{conn: conn} do
      # Belimbing gates this action the same way (`index.blade.php:6-12`,
      # `@if ($canCreate)`). Without it the create screen is reachable only by
      # typing the URL, which is how it shipped in #221.
      grant_capabilities!(["admin.authz.role.list", "admin.authz.role.create"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/authz/roles")

      # Asserted as an anchor, not just by id. `<.button>` renders a `<button>`
      # unless it is given navigate/href/patch, so wrapping it in a `<.link>`
      # produces `<a><button>` -- invalid, and the element that takes the click
      # is not the one that navigates. An id-only assertion passes either way.
      assert has_element?(view, "a#roles-create[href='/authz/roles/create']")
      refute has_element?(view, "#roles-create button")
    end

    test "hides Create Role from an actor who cannot create", %{conn: conn} do
      {:ok, view, _html} = open_index(conn)

      refute has_element?(view, "#roles-create")
    end

    test "lists roles and marks its own nav row current", %{conn: conn, ours: ours} do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})

      {:ok, view, _html} = open_index(conn)

      assert has_element?(view, "#roles", "Auditor")
      assert has_element?(view, "#nav-admin-authz-role[aria-current='page']")
    end

    test "shows the count without dead page controls on a single page", %{
      conn: conn,
      ours: ours
    } do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})

      {:ok, view, _html} = open_index(conn)

      assert has_element?(view, "#roles-pagination-summary", "Page 1 of 1 · 1 roles")
      refute has_element?(view, "#roles-prev")
      refute has_element?(view, "#roles-next")
    end

    test "does not show another tenant's custom role", %{conn: conn, ours: ours, theirs: theirs} do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Ours", code: "ours"})
      {:ok, _} = Authz.create_role(theirs, 74, %{name: "Theirs", code: "theirs"})

      {:ok, view, _html} = open_index(conn)

      # The rule lives in Authz.list_roles/2, not the LiveView. This asserts the
      # screen inherits it -- a leak here reads as an ordinary extra row.
      assert has_element?(view, "#roles", "Ours")
      refute has_element?(view, "#roles", "Theirs")
    end

    test "filters by search and reports an empty result against the term", %{
      conn: conn,
      ours: ours
    } do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Bookkeeper", code: "bookkeeper"})

      {:ok, view, _html} = open_index(conn)

      view |> form("#roles-filters", %{"search" => "Book"}) |> render_change()

      assert has_element?(view, "#roles", "Bookkeeper")
      refute has_element?(view, "#roles", "Auditor")

      view |> form("#roles-filters", %{"search" => "zzz"}) |> render_change()
      assert render(view) =~ "No roles match zzz"
    end

    test "sorting toggles direction and survives in the URL", %{conn: conn, ours: ours} do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})

      {:ok, view, _html} = open_index(conn)

      # Assert the params, not their serialisation order -- the encoder is free
      # to reorder a map and this test should not fail when it does.
      view |> element("#roles-sort-code") |> render_click()
      assert %{"sort_by" => "code", "sort_dir" => "asc"} = patched_params(view)

      view |> element("#roles-sort-code") |> render_click()
      assert %{"sort_by" => "code", "sort_dir" => "desc"} = patched_params(view)
    end

    test "sortable headers carry aria-sort, and only the active one is set", %{
      conn: conn,
      ours: ours
    } do
      # The hand-rolled markup this screen used had no aria-sort at all; the
      # shared primitive supplies it, and losing it again would be invisible
      # without this assertion.
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})

      {:ok, view, _html} = open_index(conn)

      assert has_element?(view, "th[aria-sort='ascending']")
      assert has_element?(view, "th[scope='col'][aria-sort='none']")

      view |> element("#roles-sort-code") |> render_click()

      assert %{"sort_by" => "code", "sort_dir" => "asc"} = patched_params(view)
    end

    test "renders the empty state through the shared table", %{conn: conn} do
      {:ok, view, _html} = open_index(conn)

      # The `:empty` slot is caller-guarded, so a wrong guard renders it over a
      # populated table or never at all.
      assert has_element?(view, "#roles-empty", "No roles are visible in this tenant")

      view |> form("#roles-filters", %{"search" => "zzz"}) |> render_change()
      assert has_element?(view, "#roles-empty", "No roles match zzz")
    end

    test "a hand-edited sort column falls back instead of crashing", %{conn: conn} do
      grant_capabilities!("admin.authz.role.list")

      # String.to_existing_atom on unvalidated input is the classic way this
      # page would 500 on a URL somebody typed.
      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/authz/roles?sort_by=drop_table&page=notanumber")

      assert has_element?(view, "#roles-search")
    end
  end

  describe "show" do
    test "redirects away without admin.authz.role.view", %{conn: conn, ours: ours} do
      {:ok, role} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/authz/roles/#{role.id}")
    end

    test "shows capabilities and principals", %{conn: conn, ours: ours} do
      {:ok, role} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})
      grant_capabilities!(["admin.authz.role.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/authz/roles/#{role.id}")

      assert has_element?(view, "h1", "Auditor")
      assert has_element?(view, "#role-back[href='/authz/roles']", "Back to roles")
      assert has_element?(view, "#role-summary", "Custom")
      assert has_element?(view, "#role-principals")
      assert has_element?(view, "#role-principals-empty", "Nobody in this tenant holds this role")
    end

    test "labels a principal by what it means, not the stored word", %{conn: conn, ours: ours} do
      {:ok, role} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})
      {:ok, :assigned} = Authz.assign_role(ours, 73, :agent, 7, role.id)
      grant_capabilities!(["admin.authz.role.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/authz/roles/#{role.id}")

      # principal_type is a :string column. Matching atoms fell through
      # silently and rendered the raw "agent"; nothing but an assertion on the
      # label itself would notice.
      assert has_element?(view, "#role-principals", "Employee")
      refute has_element?(view, "#role-principals", "agent")
    end

    test "another tenant's role is not found rather than forbidden", %{
      conn: conn,
      theirs: theirs
    } do
      {:ok, role} = Authz.create_role(theirs, 74, %{name: "Theirs", code: "theirs"})
      grant_capabilities!(["admin.authz.role.view", "admin.authz.role.list"])

      # Distinguishing "forbidden" from "missing" would confirm the role exists.
      assert {:error, {:live_redirect, %{to: "/authz/roles"}}} =
               conn |> log_in_as() |> live(~p"/authz/roles/#{role.id}")
    end

    test "a non-numeric id redirects instead of raising", %{conn: conn} do
      grant_capabilities!(["admin.authz.role.view", "admin.authz.role.list"])

      assert {:error, {:live_redirect, %{to: "/authz/roles"}}} =
               conn |> log_in_as() |> live(~p"/authz/roles/not-an-id")
    end
  end

  describe "create" do
    # Both capabilities, because that is the actor who actually administers
    # roles: create alone cannot open the Show page it now lands on. The
    # create-only actor is exercised separately.
    defp open_create(conn) do
      grant_capabilities!(["admin.authz.role.create", "admin.authz.role.view"])
      conn |> log_in_as() |> live(~p"/authz/roles/create")
    end

    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/roles/create")
    end

    test "redirects away without admin.authz.role.create", %{conn: conn} do
      grant_capabilities!("admin.authz.role.list")

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/authz/roles/create")
    end

    test "the literal path wins over /authz/roles/:id", %{conn: conn} do
      # Declared before the parameterised route. If that order is ever lost,
      # RoleShowLive matches "create" as an id and redirects instead, so this
      # asserts the form renders rather than merely that the request succeeds.
      {:ok, view, _html} = open_create(conn)

      assert has_element?(view, "#role-form")
      assert has_element?(view, "#role-back[href='/authz/roles']", "Back to roles")
      assert has_element?(view, "#role-cancel[href='/authz/roles']", "Cancel")
    end

    test "creates a company-owned role and lands on it", %{conn: conn, ours: ours} do
      {:ok, view, _html} = open_create(conn)

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> form("#role-form", %{
                 "role" => %{
                   "company_id" => "73",
                   "name" => "Billing Manager",
                   "code" => "billing_manager",
                   "description" => "Handles invoices"
                 }
               })
               |> render_submit()

      created = ours |> Authz.list_roles() |> Enum.find(&(&1.code == "billing_manager"))

      # A new role has no capabilities; Show is where they get granted (#269).
      assert path == "/authz/roles/#{created.id}"

      assert created.name == "Billing Manager"
      # create_role/3 forces both, so a system role can never be built here.
      refute created.is_system
      assert created.company_id == 73
    end

    test "rejects a code the database format constraint would refuse", %{conn: conn} do
      {:ok, view, _html} = open_create(conn)

      html =
        view
        |> form("#role-form", %{
          "role" => %{"company_id" => "73", "name" => "Bad", "code" => "Billing Manager"}
        })
        |> render_submit()

      assert html =~ "lowercase letters, digits and underscores"
      assert has_element?(view, "#role-form")
    end

    test "surfaces a duplicate code on the field the user can edit", %{conn: conn, ours: ours} do
      {:ok, _} = Authz.create_role(ours, 73, %{name: "Auditor", code: "auditor"})

      {:ok, view, _html} = open_create(conn)

      # Uniqueness is the database's to enforce -- the form cannot know it
      # without racing -- so the domain changeset error has to land back on
      # :code rather than surfacing as a crash or a bare flash.
      html =
        view
        |> form("#role-form", %{
          "role" => %{"company_id" => "73", "name" => "Auditor Again", "code" => "auditor"}
        })
        |> render_submit()

      assert html =~ "has already been taken"
      assert has_element?(view, "#role-form")
    end

    test "carries the confirmation onto the role it lands on", %{conn: conn} do
      # push_navigate crosses a LiveView boundary, which is where a flash can
      # quietly be dropped -- and the flash is the only thing telling the
      # operator the create succeeded once they are looking at Show.
      grant_capabilities!(["admin.authz.role.create", "admin.authz.role.view"])
      authed = log_in_as(conn)
      {:ok, view, _html} = live(authed, ~p"/authz/roles/create")

      result =
        view
        |> form("#role-form", %{
          "role" => %{"company_id" => "73", "name" => "Registrar", "code" => "registrar"}
        })
        |> render_submit()

      # `follow_redirect/2` needs the *authenticated* conn; handing it the bare
      # test conn lands on the login page with the flash intact, which looks
      # like a product bug and is not one.
      {:ok, _show, html} = follow_redirect(result, authed)

      assert html =~ "Role created."
      assert html =~ "Registrar"
    end

    test "falls back to the index for an actor who can list but not view", %{
      conn: conn,
      ours: ours
    } do
      grant_capabilities!(["admin.authz.role.create", "admin.authz.role.list"])
      authed = log_in_as(conn)
      {:ok, view, _html} = live(authed, ~p"/authz/roles/create")

      result =
        view
        |> form("#role-form", %{
          "role" => %{"company_id" => "73", "name" => "Clerk", "code" => "clerk"}
        })
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/authz/roles"}}} = result

      # Followed, not just asserted. The index is itself gated on role.list, so
      # a redirect this actor cannot complete would look identical here.
      {:ok, _index, html} = follow_redirect(result, authed)
      assert html =~ "Role created."

      assert ours |> Authz.list_roles() |> Enum.any?(&(&1.code == "clerk"))
    end

    test "stays on the form for an actor who can only create", %{conn: conn, ours: ours} do
      # create without view or list. Every other landing page is gated on a
      # capability this actor lacks, so navigating anywhere bounces them to the
      # dashboard -- the outcome this whole change exists to avoid. Staying put
      # shows the confirmation and lets them create another.
      grant_capabilities!("admin.authz.role.create")
      authed = log_in_as(conn)
      {:ok, view, _html} = live(authed, ~p"/authz/roles/create")

      html =
        view
        |> form("#role-form", %{
          "role" => %{"company_id" => "73", "name" => "Clerk", "code" => "clerk"}
        })
        |> render_submit()

      assert html =~ "Role created."
      assert has_element?(view, "#role-form")
      assert ours |> Authz.list_roles() |> Enum.any?(&(&1.code == "clerk"))
    end

    test "offers every company in the tenant and nobody else's", %{conn: conn} do
      CompanyFixtures.insert_company!(%{
        id: 75,
        tenant_id: 41,
        name: "Anvil Works",
        code: "anvil"
      })

      {:ok, view, _html} = open_create(conn)

      assert has_element?(view, "select#role-company-scope")
      assert has_element?(view, "#role-company-scope option[value='73']")
      assert has_element?(view, "#role-company-scope option[value='75']")

      # Company 74 belongs to tenant 42. A picker that offered it would be a
      # tenancy leak the user could see, and then act on.
      refute has_element?(view, "#role-company-scope option[value='74']")
    end

    test "preselects the session company when it is one of the options", %{conn: conn} do
      {:ok, view, _html} = open_create(conn)

      assert has_element?(view, "#role-company-scope option[value='73'][selected]")
    end

    test "will not create a role with no company chosen", %{conn: conn, ours: ours} do
      {:ok, view, _html} = open_create(conn)

      html =
        view
        |> form("#role-form", %{
          "role" => %{"company_id" => "", "name" => "Nobody", "code" => "nobody"}
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert has_element?(view, "#role-form")
      assert ours |> Authz.list_roles() |> Enum.all?(&(&1.code != "nobody"))
    end

    test "creates a role owned by a different company in the tenant", %{conn: conn, ours: ours} do
      # The case the session binding could not express: a tenant administrator
      # creating a role for a subsidiary without switching session context.
      CompanyFixtures.insert_company!(%{
        id: 75,
        tenant_id: 41,
        name: "Anvil Works",
        code: "anvil"
      })

      {:ok, view, _html} = open_create(conn)

      assert {:error, {:live_redirect, %{to: _path}}} =
               view
               |> form("#role-form", %{
                 "role" => %{"company_id" => "75", "name" => "Foreman", "code" => "foreman"}
               })
               |> render_submit()

      created = ours |> Authz.list_roles() |> Enum.find(&(&1.code == "foreman"))

      assert created.company_id == 75
      refute created.is_system
    end

    test "refuses a company the picker never offered, however it was submitted", %{
      conn: conn,
      ours: ours,
      theirs: theirs
    } do
      {:ok, view, _html} = open_create(conn)

      # Sent as raw events, not through `form/3`: LiveViewTest refuses to submit
      # a select value the page never offered, which is the client-side
      # assumption these payloads exist to go around. 74 belongs to another
      # tenant, 0 and 999 are tampering. All must land on the field.
      for tampered <- ["74", "0", "999"] do
        html =
          render_submit(view, :save, %{
            "role" => %{"company_id" => tampered, "name" => "Trespass", "code" => "trespass"}
          })

        assert html =~ "is not a company you can create roles for",
               "company_id=#{tampered} was not rejected on the form"
      end

      assert ours |> Authz.list_roles() |> Enum.all?(&(&1.code != "trespass"))
      assert theirs |> Authz.list_roles() |> Enum.all?(&(&1.code != "trespass"))
    end

    test "fails closed when the chosen company leaves scope after the page loads", %{
      conn: conn,
      ours: ours
    } do
      CompanyFixtures.insert_company!(%{
        id: 75,
        tenant_id: 41,
        name: "Anvil Works",
        code: "anvil"
      })

      {:ok, view, _html} = open_create(conn)

      # The options were read at mount. Form-level inclusion cannot see this,
      # which is precisely why the domain check in create_role/3 stays: the
      # window between rendering a picker and acting on it belongs to the
      # domain, not the form.
      Bilimbi.Base.Repo.query!("UPDATE companies SET deleted_at = NOW() WHERE id = 75")

      html =
        view
        |> form("#role-form", %{
          "role" => %{"company_id" => "75", "name" => "Foreman", "code" => "foreman"}
        })
        |> render_submit()

      assert html =~ "no longer available"
      assert ours |> Authz.list_roles() |> Enum.all?(&(&1.code != "foreman"))
    end
  end
end
