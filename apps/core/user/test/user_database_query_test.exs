defmodule Bilimbi.Core.UserDatabaseQueryTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.DatabaseQuery

  import Bilimbi.Core.User.TestFixtures

  setup do
    create_user_tables!()
    create_user_database_queries_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    insert_user!(%{
      id: 101,
      company_id: 73,
      name: "Test User",
      email: "test@example.com"
    })

    insert_user!(%{
      id: 102,
      company_id: 73,
      name: "Other User",
      email: "other@example.com"
    })

    {:ok, scope} = Tenancy.scope(41)

    %{scope: scope, user_id: 101, other_user_id: 102}
  end

  describe "create_database_query/3" do
    test "creates a database query with generated unique slug", %{scope: scope, user_id: user_id} do
      attrs = %{
        name: "Active Users Report",
        sql_query: "SELECT * FROM users WHERE active = true",
        description: "List of active users",
        prompt: "Show me all active users"
      }

      assert {:ok, %DatabaseQuery{} = query} = User.create_database_query(scope, user_id, attrs)
      assert query.name == "Active Users Report"
      assert query.slug == "active-users-report"
      assert query.sql_query == "SELECT * FROM users WHERE active = true"
      assert query.description == "List of active users"
      assert query.user_id == user_id
    end

    test "generates sequential suffix for duplicate slug names for the same user", %{
      scope: scope,
      user_id: user_id
    } do
      attrs = %{
        name: "Report",
        sql_query: "SELECT 1"
      }

      assert {:ok, q1} = User.create_database_query(scope, user_id, attrs)
      assert q1.slug == "report"

      assert {:ok, q2} = User.create_database_query(scope, user_id, attrs)
      assert q2.slug == "report-2"

      assert {:ok, q3} = User.create_database_query(scope, user_id, attrs)
      assert q3.slug == "report-3"
    end

    test "allows same slug for different users", %{
      scope: scope,
      user_id: user_id,
      other_user_id: other_user_id
    } do
      attrs = %{
        name: "Report",
        sql_query: "SELECT 1"
      }

      assert {:ok, q1} = User.create_database_query(scope, user_id, attrs)
      assert q1.slug == "report"

      assert {:ok, q2} = User.create_database_query(scope, other_user_id, attrs)
      assert q2.slug == "report"
    end

    test "requires name and sql_query", %{scope: scope, user_id: user_id} do
      assert {:error, changeset} = User.create_database_query(scope, user_id, %{})
      assert %{name: ["can't be blank"], sql_query: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_database_query/3" do
    test "retrieves query by ID or slug", %{scope: scope, user_id: user_id} do
      {:ok, created} =
        User.create_database_query(scope, user_id, %{
          name: "Sales Query",
          sql_query: "SELECT 100"
        })

      assert {:ok, query_by_id} = User.get_database_query(scope, user_id, created.id)
      assert query_by_id.id == created.id

      assert {:ok, query_by_slug} = User.get_database_query(scope, user_id, created.slug)
      assert query_by_slug.id == created.id
    end

    test "returns :not_found for queries belonging to another user", %{
      scope: scope,
      user_id: user_id,
      other_user_id: other_user_id
    } do
      {:ok, created} =
        User.create_database_query(scope, user_id, %{
          name: "Private Query",
          sql_query: "SELECT 1"
        })

      assert {:error, :not_found} = User.get_database_query(scope, other_user_id, created.id)
      assert {:error, :not_found} = User.get_database_query(scope, other_user_id, created.slug)
    end
  end

  describe "list_database_queries/3" do
    test "lists only queries owned by the user, with search and ordering", %{
      scope: scope,
      user_id: user_id,
      other_user_id: other_user_id
    } do
      {:ok, _q1} =
        User.create_database_query(scope, user_id, %{
          name: "Beta Report",
          description: "Monthly summary",
          sql_query: "SELECT 1"
        })

      {:ok, _q2} =
        User.create_database_query(scope, user_id, %{
          name: "Alpha Report",
          description: "Weekly summary",
          sql_query: "SELECT 2"
        })

      {:ok, _other_q} =
        User.create_database_query(scope, other_user_id, %{
          name: "Gamma Report",
          sql_query: "SELECT 3"
        })

      # User sees only their queries sorted by name ascending
      {:ok, user_queries} =
        User.list_database_queries(scope, user_id, sort_by: :name, sort_dir: :asc)

      assert length(user_queries) == 2
      assert Enum.map(user_queries, & &1.name) == ["Alpha Report", "Beta Report"]

      # Search filter
      {:ok, filtered} = User.list_database_queries(scope, user_id, search: "weekly")
      assert length(filtered) == 1
      assert hd(filtered).name == "Alpha Report"
    end
  end

  describe "update_database_query/4" do
    test "updates query fields", %{scope: scope, user_id: user_id} do
      {:ok, query} =
        User.create_database_query(scope, user_id, %{
          name: "Old Name",
          sql_query: "SELECT 1"
        })

      assert {:ok, updated} =
               User.update_database_query(scope, user_id, query.id, %{
                 name: "New Name",
                 sql_query: "SELECT 2",
                 description: "Updated description"
               })

      assert updated.name == "New Name"
      assert updated.sql_query == "SELECT 2"
      assert updated.description == "Updated description"
    end

    test "cannot reassign query to another user", %{
      scope: scope,
      user_id: user_id,
      other_user_id: other_user_id
    } do
      {:ok, query} =
        User.create_database_query(scope, user_id, %{
          name: "Owner Protected",
          sql_query: "SELECT 1"
        })

      assert {:ok, updated} =
               User.update_database_query(scope, user_id, query.id, %{
                 name: "Attempted Transfer",
                 user_id: other_user_id
               })

      assert updated.user_id == user_id
      assert {:ok, refetched} = User.get_database_query(scope, user_id, query.id)
      assert refetched.user_id == user_id
      assert {:error, :not_found} = User.get_database_query(scope, other_user_id, query.id)
    end
  end

  describe "delete_database_query/3" do
    test "deletes user's query", %{scope: scope, user_id: user_id} do
      {:ok, query} =
        User.create_database_query(scope, user_id, %{
          name: "To Delete",
          sql_query: "SELECT 1"
        })

      assert {:ok, _deleted} = User.delete_database_query(scope, user_id, query.id)
      assert {:error, :not_found} = User.get_database_query(scope, user_id, query.id)
    end
  end

  describe "duplicate_database_query/3" do
    test "creates an exact duplicate with (Copy) name and unique slug", %{
      scope: scope,
      user_id: user_id
    } do
      {:ok, original} =
        User.create_database_query(scope, user_id, %{
          name: "Original Query",
          prompt: "Some prompt",
          sql_query: "SELECT 42",
          description: "Original description"
        })

      assert {:ok, copy} = User.duplicate_database_query(scope, user_id, original.id)
      assert copy.id != original.id
      assert copy.name == "Original Query (Copy)"
      assert copy.slug == "original-query-copy"
      assert copy.sql_query == original.sql_query
      assert copy.description == original.description
      assert copy.prompt == original.prompt
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
