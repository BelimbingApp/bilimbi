defmodule Bilimbi.Core.UserTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Summary

  import Bilimbi.Core.User.TestFixtures

  setup do
    create_user_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant A"})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Company A", code: "a"})

    CompanyFixtures.insert_tenant!(%{id: 42, name: "Tenant B", is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 74, tenant_id: 42, name: "Company B", code: "b"})

    {:ok, scope_a} = Tenancy.scope(41)
    {:ok, scope_b} = Tenancy.scope(42)

    %{scope_a: scope_a, scope_b: scope_b}
  end

  describe "tenant boundary" do
    test "a company in another tenant is not found", %{scope_b: scope_b} do
      assert {:error, :company_not_found} = User.list_company_users(scope_b, 73)
      assert {:error, :company_not_found} = User.get_user(scope_b, 73, 91)

      assert {:error, :company_not_found} =
               User.create_user(scope_b, 73, valid_attributes())
    end

    test "users are listed only for their own company", %{scope_a: scope_a, scope_b: scope_b} do
      insert_user!(%{id: 91, company_id: 73, email: "a@example.com"})
      insert_user!(%{id: 92, company_id: 74, email: "b@example.com"})

      assert {:ok, [%Summary{id: 91}]} = User.list_company_users(scope_a, 73)
      assert {:ok, [%Summary{id: 92}]} = User.list_company_users(scope_b, 74)
    end

    test "a user with no company appears in no company list", %{scope_a: scope_a} do
      insert_user!(%{id: 93, company_id: nil, email: "orphan@example.com"})

      assert {:ok, users} = User.list_company_users(scope_a, 73)
      refute Enum.any?(users, &(&1.id == 93))
    end
  end

  describe "credentials" do
    test "stores a supplied bcrypt hash unchanged", %{scope_a: scope_a} do
      assert {:ok, %Summary{id: id}} = User.create_user(scope_a, 73, valid_attributes())
      assert stored_password(id) == password_hash()
    end

    test "rejects a plaintext password", %{scope_a: scope_a} do
      attributes = Map.put(valid_attributes(), :password_hash, "hunter2")

      assert {:error, changeset} = User.create_user(scope_a, 73, attributes)
      assert %{password_hash: ["must be a bcrypt crypt-format hash"]} = errors_on(changeset)
    end

    test "rejects a missing credential", %{scope_a: scope_a} do
      attributes = Map.delete(valid_attributes(), :password_hash)

      assert {:error, changeset} = User.create_user(scope_a, 73, attributes)
      assert %{password: ["can't be blank"]} = errors_on(changeset)
    end

    test "the credential never reaches the read model", %{scope_a: scope_a} do
      {:ok, summary} = User.create_user(scope_a, 73, valid_attributes())

      refute summary |> Map.from_struct() |> Map.has_key?(:password)
      refute summary |> Map.from_struct() |> Map.has_key?(:remember_token)
    end
  end

  describe "employee affiliation" do
    test "accepts an employee in the same company", %{scope_a: scope_a} do
      {:ok, employee} = create_employee(scope_a, 73, "EMP-1")

      attributes = Map.put(valid_attributes(), :employee_id, employee.id)

      assert {:ok, %Summary{employee_id: employee_id}} =
               User.create_user(scope_a, 73, attributes)

      assert employee_id == employee.id
    end

    test "rejects an employee from another company", %{scope_a: scope_a, scope_b: scope_b} do
      {:ok, other} = create_employee(scope_b, 74, "EMP-2")

      attributes = Map.put(valid_attributes(), :employee_id, other.id)

      assert {:error, changeset} = User.create_user(scope_a, 73, attributes)
      assert %{employee_id: ["does not belong to the company"]} = errors_on(changeset)
    end
  end

  describe "lifecycle" do
    test "get, update, and delete are company-scoped", %{scope_a: scope_a} do
      {:ok, %Summary{id: id}} = User.create_user(scope_a, 73, valid_attributes())

      assert {:ok, %Summary{name: "Ada Lovelace"}} = User.get_user(scope_a, 73, id)

      assert {:ok, %Summary{name: "Ada L"}} =
               User.update_user(scope_a, 73, id, %{name: "Ada L"})

      assert :ok = User.delete_user(scope_a, 73, id)
      assert {:error, :user_not_found} = User.get_user(scope_a, 73, id)
    end

    test "rejects a duplicate email", %{scope_a: scope_a} do
      {:ok, _} = User.create_user(scope_a, 73, valid_attributes())

      assert {:error, changeset} = User.create_user(scope_a, 73, valid_attributes())
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  test "publishes the durable Laravel notifiable identity" do
    assert User.notifiable_identity() == "App\\Core\\User\\Models\\User"
  end

  defp valid_attributes do
    %{name: "Ada Lovelace", email: "ada@example.com", password_hash: password_hash()}
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp create_employee(scope, company_id, number) do
    :ok = Employee.ensure_system_types()

    Employee.create_employee(scope, company_id, %{
      employee_number: number,
      full_name: "Grace Hopper",
      employee_type: "full_time"
    })
  end
end
