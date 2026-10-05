defmodule BilimbiWeb.ConnCase do
  @moduledoc """
  The case template for every web test (host tests and module `web_test/`).

  Every test gets, without asking:

  - a sandbox owner (shared unless the test is `async: true`) and a fresh
    `conn`;
  - the temporary tables the shell reads on every page: sessions, authz,
    settings, audit, perf, notifications, GeoNames and addresses. Do not
    create them again in a test; a missing table is a `42P01` that a
    caller's fallback would otherwise swallow.

  The default signed-in identity is tenant 41, company 73, user 91
  ("Ada Lovelace"), which are the defaults of the owner fixtures
  (`Tenancy`, `Company` and `User` `TestFixtures`). A test inserts those rows
  with `signed_in_identity!/0`. `log_in_as/2` needs user 91 (or the one it is
  given) to exist, because request rehydration loads the user.
  """

  use ExUnit.CaseTemplate

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Tenancy

  using do
    quote do
      # The default endpoint for testing
      @endpoint BilimbiWeb.Endpoint

      use BilimbiWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import BilimbiWeb.ConnCase
    end
  end

  setup tags do
    owner =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Bilimbi.Base.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    create_required_web_tables!()

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  # Fixture modules are loaded from test_helper.exs after this file compiles.
  # Concatenate from strings so `alias Bilimbi.Base.Session` does not nest.
  #
  # Session, authz, settings, audit, and notification tables belong here so
  # that common web components (such as dashboard widgets, topbars, bell
  # notifications, and navigation) never raise `undefined_table` (42P01)
  # and get silently masked by fallbacks (#359, #365, #409).
  defp create_required_web_tables! do
    apply(Module.concat(["Bilimbi.Base.Session.TestFixtures"]), :create_sessions_table!, [])
    apply(Module.concat(["Bilimbi.Base.Authz.TestFixtures"]), :create_authz_tables!, [])
    apply(Module.concat(["Bilimbi.Base.Settings.TestFixtures"]), :create_settings_table!, [])
    apply(Module.concat(["Bilimbi.Base.Audit.TestFixtures"]), :create_audit_tables!, [])
    apply(Module.concat(["Bilimbi.Base.Perf.TestFixtures"]), :create_perf_table!, [])
    apply(Module.concat(["Bilimbi.Core.User.TestFixtures"]), :create_notifications_table!, [])
    apply(Module.concat(["Bilimbi.Core.User.TestFixtures"]), :create_user_pins_table!, [])

    # Employee Show loads attached addresses on mount, and both the show suite
    # and the form suite (which redirects into it) reach them. Until #409 the
    # 42P01 raised here was caught by a `rescue _ -> []`, so every one of those
    # tests rendered an employee with no addresses and none of them knew.
    # `addresses` has foreign keys into both geonames tables, so those go first.
    apply(Module.concat(["Bilimbi.Core.Geonames.TestFixtures"]), :create_geonames_tables!, [])
    apply(Module.concat(["Bilimbi.Core.Address.TestFixtures"]), :create_address_tables!, [])
  end

  @doc """
  Creates the user tables and inserts the default signed-in identity: tenant
  41, company 73 and user 91 ("Ada Lovelace"), every value being the owner
  fixture's default. A test that needs a different identity calls the owner
  fixtures itself.
  """
  def signed_in_identity! do
    apply(Module.concat(["Bilimbi.Core.User.TestFixtures"]), :create_user_tables!, [])
    apply(Module.concat(["Bilimbi.Core.Company.TestFixtures"]), :insert_tenant!, [%{id: 41}])

    apply(Module.concat(["Bilimbi.Core.Company.TestFixtures"]), :insert_company!, [
      %{id: 73, tenant_id: 41}
    ])

    apply(Module.concat(["Bilimbi.Core.User.TestFixtures"]), :insert_user!, [
      %{id: 91, company_id: 73}
    ])

    :ok
  end

  @doc """
  Stable IDs as `BilimbiWeb.UserAuth.session_user/1` produces them for the
  login token. Display fields are not part of the cookie.
  """
  def session_user(overrides \\ %{}) do
    Map.merge(
      %{
        "user_id" => 91,
        "company_id" => 73
      },
      overrides
    )
  end

  @doc """
  Puts a signed-in Phoenix cookie backed by a durable Base Session row.

  The cookie carries only `session_id`, `user_id`, and `company_id`. The
  matching user must already exist so request rehydration can succeed.
  """
  def log_in_as(conn, session_user \\ session_user()) do
    user_id = Map.fetch!(session_user, "user_id")
    company_id = Map.fetch!(session_user, "company_id")
    session_id = Map.get(session_user, "session_id") || generate_session_id()

    {:ok, _entry} =
      Session.put_session(session_id, "{}", %{
        user_id: user_id,
        last_activity: System.system_time(:second)
      })

    Phoenix.ConnTest.init_test_session(conn, %{
      "current_user" => %{
        "session_id" => session_id,
        "user_id" => user_id,
        "company_id" => company_id
      },
      "live_socket_id" => BilimbiWeb.UserAuth.live_socket_id(session_id)
    })
  end

  @doc """
  Marks a signed-in conn as an operator impersonating the signed-in user, with
  the session shape `BilimbiWeb.UserAuth` reads. Call it after `log_in_as/2`.
  """
  def impersonating_as(conn, original_user_id, original_user_name) do
    Phoenix.ConnTest.init_test_session(conn, %{
      BilimbiWeb.UserAuth.impersonation_key() => %{
        "original_user_id" => original_user_id,
        "original_user_name" => original_user_name
      }
    })
  end

  @doc """
  The query parameters of the URL the view just patched to.
  """
  def patched_params(view) do
    Phoenix.LiveViewTest.assert_patch(view)
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end

  @doc """
  Asserts that a shared `<.modal>` with this DOM id is open and carries the
  dialog semantics assistive technology relies on: a modal `<dialog>` named
  by its visible title and driven by the `Modal` hook.

  The hook's browser behaviour (focus in, containment, Escape, focus return)
  is not observable here; the markup that enables it is.
  """
  def assert_modal_dialog(view, id, title) do
    import Phoenix.LiveViewTest, only: [has_element?: 2, has_element?: 3]

    selector =
      ~s(dialog##{id}[open][aria-modal="true"][aria-labelledby="#{id}-title"][phx-hook="Modal"])

    ExUnit.Assertions.assert(has_element?(view, selector),
      message: "expected an open modal dialog ##{id} with dialog semantics"
    )

    ExUnit.Assertions.assert(has_element?(view, "dialog##{id} h2##{id}-title", title),
      message: "expected modal dialog ##{id} to be titled #{inspect(title)}"
    )

    ExUnit.Assertions.assert(
      has_element?(view, "dialog##{id} ##{id}-client-error[phx-disconnected][phx-connected]"),
      message:
        "expected modal dialog ##{id} to carry its own connection banners, wired to " <>
          "reveal on a dropped socket, since the layout's are inert and dimmed while it is open"
    )
  end

  @doc """
  Grants direct Authz capabilities to the signed-in test user against their
  live company. Uses the real contribution registry, not the Authz test snapshot.
  """
  def grant_capabilities!(capabilities, opts \\ []) do
    tenant_id = Keyword.get(opts, :tenant_id, 41)
    company_id = Keyword.get(opts, :company_id, 73)
    user_id = Keyword.get(opts, :user_id, 91)
    {:ok, scope} = Tenancy.scope(tenant_id)

    Enum.each(List.wrap(capabilities), fn capability ->
      {:ok, :stored} =
        Authz.put_principal_capability(scope, company_id, :user, user_id, capability, true)
    end)

    :ok
  end

  @doc """
  Drops the signed-in user's direct grant of `capability`, so a page that
  mounted with it must refuse the next write on its own. `scope` is the
  tenant's, as `Tenancy.scope/1` returns it.
  """
  def revoke_capability!(scope, capability) do
    grant =
      Authz.list_principal_capabilities(scope, page_size: 100)
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == capability))

    {:ok, :removed} = Authz.remove_principal_capability(scope, grant.id)
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
