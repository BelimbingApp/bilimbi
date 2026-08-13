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

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  A session map as `BilimbiWeb.UserAuth.session_user/1` produces it: the
  user summary fields plus the tenant resolved at the login edge.
  """
  def session_user(overrides \\ %{}) do
    Map.merge(
      %{
        "user_id" => 91,
        "name" => "Ada Lovelace",
        "email" => "ada@example.com",
        "company_id" => 73,
        "company_name" => "Bilimbi Development",
        "tenant_id" => 41
      },
      overrides
    )
  end

  @doc "Puts a signed-in session on the connection."
  def log_in_as(conn, session_user \\ session_user()) do
    Phoenix.ConnTest.init_test_session(conn, %{"current_user" => session_user})
  end
end
