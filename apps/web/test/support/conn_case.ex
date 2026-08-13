defmodule BilimbiWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use BilimbiWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
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

    create_session_and_authz_tables!()

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  # Fixture modules are loaded from test_helper.exs after this file compiles.
  # Concatenate from strings so `alias Bilimbi.Base.Session` does not nest.
  defp create_session_and_authz_tables! do
    apply(Module.concat(["Bilimbi.Base.Session.TestFixtures"]), :create_sessions_table!, [])
    apply(Module.concat(["Bilimbi.Base.Authz.TestFixtures"]), :create_authz_tables!, [])
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
      }
    })
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

  defp generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
