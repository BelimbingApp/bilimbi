defmodule Bilimbi.Base.Database.QueryExecutorTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.QueryExecutor

  describe "extract_named_parameters/1" do
    test "extracts named parameters" do
      sql = "SELECT * FROM users WHERE status = :status AND age > :min_age"
      assert QueryExecutor.extract_named_parameters(sql) == ["status", "min_age"]
    end

    test "ignores parameters inside string literals" do
      sql = "SELECT ':not_a_param' AS val, * FROM users WHERE status = :status"
      assert QueryExecutor.extract_named_parameters(sql) == ["status"]
    end

    test "ignores PostgreSQL type casts like ::int" do
      sql = "SELECT id::int FROM users WHERE id = :user_id"
      assert QueryExecutor.extract_named_parameters(sql) == ["user_id"]
    end

    test "ignores comments" do
      sql = """
      -- Comment with :ignored_1
      /* Block comment with :ignored_2 */
      SELECT * FROM users WHERE active = :active
      """

      assert QueryExecutor.extract_named_parameters(sql) == ["active"]
    end
  end

  describe "execute_readonly/3" do
    test "executes simple select query" do
      assert {:ok, result} = Database.execute_readonly("SELECT 1 AS num, 'test' AS label")
      assert result.columns == ["num", "label"]
      assert result.rows == [%{"num" => 1, "label" => "test"}]
      assert result.total == 1
      assert result.page == 1
      assert result.per_page == 25
      assert result.last_page == 1
    end

    test "executes query with named parameters" do
      sql = "SELECT :greeting || ', ' || :name AS msg"
      params = %{"greeting" => "Hello", "name" => "World"}

      assert {:ok, result} = Database.execute_readonly(sql, params)
      assert result.rows == [%{"msg" => "Hello, World"}]
    end

    test "executes query with WITH clause" do
      sql = "WITH vals AS (SELECT 42 AS answer) SELECT answer * 2 AS doubled FROM vals"

      assert {:ok, result} = Database.execute_readonly(sql)
      assert result.rows == [%{"doubled" => 84}]
    end

    test "binds atom-keyed params and preserves a false value" do
      sql = "SELECT :flag::boolean AS flag"

      assert {:ok, result} = Database.execute_readonly(sql, %{flag: false})
      assert result.rows == [%{"flag" => false}]
    end

    test "does not mint atoms from SQL-authored parameter names" do
      # Warm the execution path first so lazy module loading cannot skew the
      # atom count; the measured call must then create zero atoms even though
      # its parameter name has never been seen by this VM.
      assert {:ok, _} = Database.execute_readonly("SELECT :warm::text AS v", %{"warm" => "x"})

      atom_count_before = :erlang.system_info(:atom_count)
      param = "zz_#{System.unique_integer([:positive])}"

      assert {:ok, result} =
               Database.execute_readonly("SELECT :#{param}::text AS v", %{param => "x"})

      assert result.rows == [%{"v" => "x"}]
      assert :erlang.system_info(:atom_count) == atom_count_before
    end

    test "supports pagination and sorting" do
      sql = "SELECT generate_series(1, 10) AS num"

      assert {:ok, result} =
               Database.execute_readonly(sql, %{},
                 page: 2,
                 per_page: 3,
                 order_by: "num",
                 order_dir: :desc
               )

      assert result.total == 10
      assert result.page == 2
      assert result.per_page == 3
      assert result.last_page == 4
      assert result.rows == [%{"num" => 7}, %{"num" => 6}, %{"num" => 5}]
    end

    test "rejects empty SQL" do
      assert {:error, "Query cannot be empty."} = Database.execute_readonly("   ")
    end

    test "rejects non-SELECT/WITH statements" do
      assert {:error, "Only SELECT or WITH queries are permitted."} =
               Database.execute_readonly("SET search_path TO public")
    end

    test "rejects write / DDL keywords" do
      assert {:error, "Write or DDL statements are not permitted in queries."} =
               Database.execute_readonly("SELECT * FROM users; DROP TABLE users;")

      assert {:error, "Only SELECT or WITH queries are permitted."} =
               Database.execute_readonly("INSERT INTO users (name) VALUES ('attacker')")

      assert {:error, "Only SELECT or WITH queries are permitted."} =
               Database.execute_readonly("UPDATE users SET name = 'attacker'")

      assert {:error, "Only SELECT or WITH queries are permitted."} =
               Database.execute_readonly("DELETE FROM users")
    end

    test "handles syntax errors gracefully" do
      assert {:error, msg} = Database.execute_readonly("SELECT * FROM non_existent_table_xyz")
      assert msg =~ "does not exist" or msg =~ "SQL error"
    end
  end
end
