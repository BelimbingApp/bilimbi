defmodule Bilimbi.Core.UserTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings.ContributionValidator
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Contributions
  alias Bilimbi.Core.User.Summary

  import Bilimbi.Core.User.TestFixtures

  setup_all do
    settings =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "core/user"},
          payload: Contributions.contributions().settings
        }
      ])

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "core-user-test",
      consumers: %{settings: settings, authz: [], menu: []}
    })

    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  setup do
    create_user_tables!()
    SettingsFixtures.create_settings_table!()

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

  describe "list_users/1" do
    test "returns tenant users across companies ordered by id", %{
      scope_a: scope_a,
      scope_b: scope_b
    } do
      CompanyFixtures.insert_company!(%{id: 75, tenant_id: 41, code: "a2"})
      insert_user!(%{id: 91, company_id: 73, email: "a1@example.com"})
      insert_user!(%{id: 94, company_id: 75, email: "a2@example.com"})
      insert_user!(%{id: 92, company_id: 74, email: "b@example.com"})

      assert {:ok, [%Summary{id: 91}, %Summary{id: 94}]} = User.list_users(scope_a)
      assert {:ok, [%Summary{id: 92}]} = User.list_users(scope_b)
    end

    test "includes users whose company is soft-deleted", %{scope_a: scope_a} do
      CompanyFixtures.insert_company!(%{
        id: 76,
        tenant_id: 41,
        code: "soft_deleted",
        deleted_at: ~N[2026-08-11 12:00:00]
      })

      insert_user!(%{id: 95, company_id: 76, email: "soft@example.com"})
      insert_user!(%{id: 91, company_id: 73, email: "live@example.com"})

      assert {:ok, users} = User.list_users(scope_a)
      assert Enum.map(users, & &1.id) == [91, 95]

      # Would fail under option (b): soft-deleted companies excluded from listing.
      assert Enum.any?(users, &(&1.id == 95))
    end

    test "excludes users with no company and users in another tenant", %{scope_a: scope_a} do
      insert_user!(%{id: 91, company_id: 73, email: "a@example.com"})
      insert_user!(%{id: 93, company_id: nil, email: "orphan@example.com"})
      insert_user!(%{id: 92, company_id: 74, email: "b@example.com"})

      assert {:ok, [%Summary{id: 91}]} = User.list_users(scope_a)
    end
  end

  describe "get_tenant_user/2" do
    test "reads a user whose company is soft-deleted, matching list visibility", %{
      scope_a: scope_a
    } do
      CompanyFixtures.insert_company!(%{
        id: 76,
        tenant_id: 41,
        code: "soft_deleted",
        deleted_at: ~N[2026-08-11 12:00:00]
      })

      insert_user!(%{id: 95, company_id: 76, email: "soft@example.com"})

      assert {:ok, %Summary{id: 95, company_id: 76}} = User.get_tenant_user(scope_a, 95)
      assert {:error, :company_not_found} = User.get_user(scope_a, 76, 95)
    end

    test "excludes users in another tenant, with no company, or unknown", %{
      scope_a: scope_a
    } do
      insert_user!(%{id: 92, company_id: 74, email: "b@example.com"})
      insert_user!(%{id: 93, company_id: nil, email: "orphan@example.com"})

      assert {:error, :user_not_found} = User.get_tenant_user(scope_a, 92)
      assert {:error, :user_not_found} = User.get_tenant_user(scope_a, 93)
      assert {:error, :user_not_found} = User.get_tenant_user(scope_a, 99)
    end
  end

  describe "credentials" do
    test "registers with an Argon2id hash and normalizes the email", %{scope_a: scope_a} do
      assert {:ok, %Summary{id: id}} = User.create_user(scope_a, 73, valid_attributes())
      stored = stored_password(id)

      assert String.starts_with?(stored, "$argon2id$")
      assert Argon2.verify_pass("correct horse", stored)
      refute stored == "correct horse"

      assert {:ok, %Summary{email: "ada@example.com"}} =
               User.get_user(scope_a, 73, id)
    end

    test "rejects a short or pre-hashed credential", %{scope_a: scope_a} do
      assert {:error, short_changeset} =
               User.create_user(scope_a, 73, Map.put(valid_attributes(), :password, "short"))

      assert %{password: ["should be at least 8 character(s)"]} = errors_on(short_changeset)

      attributes =
        valid_attributes()
        |> Map.delete(:password)
        |> Map.put(:password_hash, password_hash())

      assert {:error, changeset} = User.create_user(scope_a, 73, attributes)
      assert %{password: ["can't be blank"]} = errors_on(changeset)
    end

    test "the credential never reaches the read model", %{scope_a: scope_a} do
      {:ok, summary} = User.create_user(scope_a, 73, valid_attributes())

      refute summary |> Map.from_struct() |> Map.has_key?(:password)
      refute summary |> Map.from_struct() |> Map.has_key?(:remember_token)
    end

    test "authenticates without exposing why a login failed" do
      insert_user!(%{email: "login@example.com", password_hash: password_hash("right-password")})

      assert {:ok, %Summary{id: 91}} = User.authenticate(" LOGIN@example.com ", "right-password")
      assert {:error, :invalid_credentials} = User.authenticate("login@example.com", "wrong")
      assert {:error, :invalid_credentials} = User.authenticate("missing@example.com", "wrong")
    end

    test "authenticates a hash produced with Belimbing's Laravel Argon2id parameters" do
      hash = laravel_argon2_password_hash()
      insert_user!(%{email: "laravel@example.com", password_hash: hash})

      assert {:ok, %Summary{id: 91}} =
               User.authenticate("laravel@example.com", "laravel-password")

      assert stored_password(91) == hash
    end

    test "upgrades a Laravel $2y$ bcrypt credential after successful login" do
      legacy_hash = legacy_password_hash("legacy-password")
      insert_user!(%{email: "legacy@example.com", password_hash: legacy_hash})

      assert stored_password(91) == legacy_hash
      assert {:ok, %Summary{id: 91}} = User.authenticate("legacy@example.com", "legacy-password")

      upgraded = stored_password(91)
      assert String.starts_with?(upgraded, "$argon2id$")
      assert Argon2.verify_pass("legacy-password", upgraded)
    end

    test "confirms and changes a password only inside the user's company", %{
      scope_a: scope_a,
      scope_b: scope_b
    } do
      insert_user!(%{password_hash: password_hash("old-password")})

      assert :ok = User.confirm_password(scope_a, 73, 91, "old-password")
      assert {:error, :invalid_password} = User.confirm_password(scope_a, 73, 91, "wrong")
      assert {:error, :company_not_found} = User.confirm_password(scope_b, 73, 91, "old-password")

      assert {:ok, %Summary{id: 91}} =
               User.change_password(scope_a, 73, 91, "old-password", "new-password")

      assert {:ok, %Summary{id: 91}} = User.authenticate("ada@example.com", "new-password")
      assert {:error, :invalid_credentials} = User.authenticate("ada@example.com", "old-password")
    end
  end

  describe "password reset" do
    test "keeps unknown-account requests neutral and never calls delivery" do
      assert :ok =
               User.request_password_reset("missing@example.com", fn _user, _token ->
                 flunk("delivery must not run for a missing account")
               end)
    end

    test "stores only a hash, throttles repeats, and resets with a valid token" do
      insert_user!(%{
        email: "reset@example.com",
        password_hash: password_hash("old-password"),
        remember_token: "stale-token"
      })

      deliver = fn user, token ->
        send(self(), {:password_reset, user, token})
        :ok
      end

      assert :ok = User.request_password_reset("reset@example.com", deliver)
      assert_receive {:password_reset, %Summary{id: 91}, token}
      refute stored_reset_token("reset@example.com") == token

      assert :ok = User.request_password_reset("reset@example.com", deliver)
      refute_receive {:password_reset, _, _}

      assert {:error, :invalid_or_expired_token} =
               User.reset_password("reset@example.com", "wrong-token", "new-password")

      assert {:ok, %Summary{id: 91}} =
               User.reset_password("reset@example.com", token, "new-password")

      assert {:ok, %Summary{id: 91}} = User.authenticate("reset@example.com", "new-password")
      refute stored_remember_token(91) in [nil, "stale-token"]

      assert {:error, :invalid_or_expired_token} =
               User.reset_password("reset@example.com", token, "another-password")
    end

    test "rejects expired tokens and validates the replacement password" do
      insert_user!(%{email: "reset@example.com"})

      assert :ok =
               User.request_password_reset(
                 "reset@example.com",
                 fn _user, token ->
                   send(self(), {:password_reset, token})
                   :ok
                 end,
                 throttle_seconds: 0
               )

      assert_receive {:password_reset, token}

      assert {:error, changeset} =
               User.reset_password("reset@example.com", token, "short")

      assert %{password: ["should be at least 8 character(s)"]} = errors_on(changeset)

      expire_reset_token!("reset@example.com")

      assert {:error, :invalid_or_expired_token} =
               User.reset_password("reset@example.com", token, "long-enough")
    end
  end

  describe "email verification" do
    @verification_secret String.duplicate("email-verification-secret-", 2)

    test "verifies an unmodified email once and is then idempotent", %{scope_a: scope_a} do
      insert_user!()

      assert {:ok, token} =
               User.issue_email_verification_token(
                 scope_a,
                 73,
                 91,
                 @verification_secret
               )

      assert {:ok, :verified, %Summary{email_verified_at: %NaiveDateTime{}}} =
               User.verify_email(scope_a, 73, token, @verification_secret)

      assert {:ok, :already_verified, %Summary{}} =
               User.verify_email(scope_a, 73, token, @verification_secret)

      assert {:error, :already_verified} =
               User.issue_email_verification_token(
                 scope_a,
                 73,
                 91,
                 @verification_secret
               )
    end

    test "rejects tampered, expired, and email-invalidated tokens", %{scope_a: scope_a} do
      insert_user!()

      assert {:ok, token} =
               User.issue_email_verification_token(
                 scope_a,
                 73,
                 91,
                 @verification_secret
               )

      assert {:error, :invalid_or_expired_token} =
               User.verify_email(scope_a, 73, token <> "tampered", @verification_secret)

      assert {:ok, expired} =
               User.issue_email_verification_token(
                 scope_a,
                 73,
                 91,
                 @verification_secret,
                 signed_at: 0
               )

      assert {:error, :invalid_or_expired_token} =
               User.verify_email(scope_a, 73, expired, @verification_secret)

      assert {:ok, %Summary{email_verified_at: nil}} =
               User.update_user(scope_a, 73, 91, %{email: "changed@example.com"})

      assert {:error, :invalid_or_expired_token} =
               User.verify_email(scope_a, 73, token, @verification_secret)
    end
  end

  describe "user preferences" do
    test "publishes the four canonical setting definitions" do
      definitions = Contributions.contributions().settings.definitions

      assert Map.keys(definitions) |> Enum.sort() == [
               "ai.last_used_model_hints",
               "ui.dashboard.layout",
               "ui.landing_menu_id",
               "ui.theme"
             ]

      assert definitions["ui.theme"] == %{
               type: :string,
               scopes: [:user],
               default: "system",
               label: "Theme",
               help: "Choose a light, dark, or operating-system-controlled color theme.",
               editable: "profile.appearance",
               capability: "base.settings.user.manage"
             }
    end

    test "resolves defaults and stores validated overrides inside the user boundary", %{
      scope_a: scope_a,
      scope_b: scope_b
    } do
      insert_user!()

      assert {:ok, preferences} = User.user_preferences(scope_a, 73, 91)
      assert preferences["ui.theme"] == "system"
      assert preferences["ui.landing_menu_id"] == ""
      assert preferences["ui.dashboard.layout"] == []
      assert preferences["ai.last_used_model_hints"] == []

      assert {:ok, "dark"} =
               User.put_user_preference(scope_a, 73, 91, "ui.theme", "dark")

      assert {:ok, "dark"} = User.get_user_preference(scope_a, 73, 91, "ui.theme")
      assert :ok = User.delete_user_preference(scope_a, 73, 91, "ui.theme")
      assert {:ok, "system"} = User.get_user_preference(scope_a, 73, 91, "ui.theme")

      assert {:error, :invalid_preference} =
               User.put_user_preference(scope_a, 73, 91, "ui.theme", "sepia")

      assert {:error, :unsupported_preference} =
               User.get_user_preference(scope_a, 73, 91, "unknown")

      assert {:error, :company_not_found} = User.user_preferences(scope_b, 73, 91)
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

    test "changing an email clears its verification timestamp", %{scope_a: scope_a} do
      insert_user!(%{email_verified_at: ~N[2026-08-13 12:00:00]})

      assert {:ok, %Summary{email: "changed@example.com", email_verified_at: nil}} =
               User.update_user(scope_a, 73, 91, %{email: "CHANGED@example.com"})
    end
  end

  test "publishes the durable Laravel notifiable identity" do
    assert User.notifiable_identity() == "App\\Core\\User\\Models\\User"
  end

  defp valid_attributes do
    %{name: "Ada Lovelace", email: " ADA@example.com ", password: "correct horse"}
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
