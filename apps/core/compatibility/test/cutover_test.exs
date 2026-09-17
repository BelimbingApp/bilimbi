defmodule Bilimbi.Core.Compatibility.CutoverTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Bilimbi.Core.Compatibility.Cutover
  alias Bilimbi.Core.User.Pin
  alias Ecto.Adapters.SQL

  describe "classify_url/1" do
    test "remaps baseline admin prefixes onto Bilimbi routes" do
      assert Cutover.classify_url("/admin/companies") == {:mapped, "/companies"}
      assert Cutover.classify_url("/admin/companies/5") == {:mapped, "/companies/5"}
      assert Cutover.classify_url("/admin/employees") == {:mapped, "/employees"}
      assert Cutover.classify_url("/admin/addresses/9") == {:mapped, "/addresses/9"}
      assert Cutover.classify_url("/admin/geonames/countries") == {:mapped, "/geonames/countries"}
      assert Cutover.classify_url("/admin/roles") == {:mapped, "/authz/roles"}
      assert Cutover.classify_url("/admin/audit/actions") == {:mapped, "/audit/actions"}
      assert Cutover.classify_url("/admin/audit/mutations") == {:mapped, "/audit/mutations"}

      assert Cutover.classify_url("/admin/authz/decision-logs") ==
               {:mapped, "/authz/decision-logs"}

      assert Cutover.classify_url("/admin/system/schedule") == {:mapped, "/system/schedule"}
      assert Cutover.classify_url("/admin/system/sessions") == {:mapped, "/system/sessions"}
      assert Cutover.classify_url("/admin/system/settings") == {:mapped, "/system/settings"}
      assert Cutover.classify_url("/admin/system/info") == {:mapped, "/system/info"}

      assert Cutover.classify_url("/admin/system/localization") ==
               {:mapped, "/system/localization"}

      assert Cutover.classify_url("/admin/system/performance") == {:mapped, "/system/performance"}
      assert Cutover.classify_url("/admin/employee-types") == {:mapped, "/employee-types"}
      assert Cutover.classify_url("/admin/users/5/edit") == {:mapped, "/users/5/edit"}
    end

    test "renames create to new only where Bilimbi uses new" do
      assert Cutover.classify_url("/admin/users/create") == {:mapped, "/users/new"}
      assert Cutover.classify_url("/admin/employees/create") == {:mapped, "/employees/new"}

      assert Cutover.classify_url("/admin/employee-types/create") ==
               {:mapped, "/employee-types/new"}

      assert Cutover.classify_url("/admin/companies/create") == {:mapped, "/companies/create"}
      assert Cutover.classify_url("/admin/addresses/create") == {:mapped, "/addresses/create"}
    end

    test "treats already-Bilimbi paths as identity" do
      assert Cutover.classify_url("/companies/5") == {:identity, "/companies/5"}
      assert Cutover.classify_url("/dashboard") == {:identity, "/dashboard"}
      assert Cutover.classify_url("/notifications") == {:identity, "/notifications"}
      assert Cutover.classify_url("/settings/profile") == {:identity, "/settings/profile"}

      assert Cutover.classify_url("/admin/system/database-queries/monthly-sales") ==
               {:identity, "/admin/system/database-queries/monthly-sales"}
    end

    test "normalizes absolute URLs and carries the sorted query through" do
      assert Cutover.classify_url("https://old.example.com/admin/companies?b=2&a=1#frag") ==
               {:mapped, "/companies?a=1&b=2"}

      assert Cutover.classify_url("/admin/companies/") == {:mapped, "/companies"}
    end

    test "leaves paths with no Bilimbi equivalent unmappable" do
      assert {kind, _} = Cutover.classify_url("/people/leave/approvals")
      assert kind == :unmappable

      for url <- [
            "/commerce/orders",
            "/agents",
            "/admin/impersonate/5",
            "/admin/ai/models",
            "/admin/users/5/delete",
            "/companies/new",
            "/admin/system/unknown-page"
          ] do
        assert Cutover.classify_url(url) == {:unmappable, Pin.normalize_url(url)},
               "expected #{url} to be unmappable"
      end
    end
  end

  describe "map_icon/1" do
    test "rewrites heroicon prefixes onto hero names" do
      assert Cutover.map_icon("heroicon-o-cog-6-tooth") == {:mapped, "hero-cog-6-tooth"}
      assert Cutover.map_icon("heroicon-s-chart-bar") == {:mapped, "hero-chart-bar-solid"}
      assert Cutover.map_icon("heroicon-m-user-plus") == {:mapped, "hero-user-plus-mini"}
    end

    test "leaves everything else as a known remainder" do
      assert Cutover.map_icon(nil) == :remainder
      assert Cutover.map_icon("") == :remainder
      assert Cutover.map_icon("hero-magnifying-glass") == :remainder
      assert Cutover.map_icon("custom-svg-thing") == :remainder
      assert Cutover.map_icon("heroicon-o-") == :remainder
    end
  end

  describe "run/1 over seeded Belimbing-shaped rows" do
    setup do
      ContributionRegistry.install!()

      UserFixtures.create_user_tables!()
      UserFixtures.create_user_pins_table!()
      UserFixtures.create_user_database_queries_table!()
      UserFixtures.create_notifications_table!()
      AuthzFixtures.create_authz_tables!()

      UserFixtures.insert_user!(%{
        id: 91,
        company_id: 73,
        name: "Ada Lovelace",
        email: "ada@example.com"
      })

      UserFixtures.insert_user!(%{
        id: 92,
        company_id: 73,
        name: "Grace Hopper",
        email: "grace@example.com"
      })

      seed_pins!()
      seed_queries!()
      nids = seed_notifications!()
      seed_grants!()

      {:ok, nids: nids}
    end

    test "remaps pins, recomputes hashes, and names every kept-broken pin" do
      assert {:ok, report} = run_cutover()
      pins = report.steps.pins

      assert pins.examined == 8
      assert pins.changed == 5
      assert pins.unchanged == 1
      assert pins.unmapped == 2
      assert pins.examined == pins.changed + pins.unchanged + pins.unmapped

      # Route + icon both move; the stale Belimbing hash is never trusted.
      assert pin_row(1).url == "/companies"
      assert pin_row(1).url_hash == Pin.hash_url("/companies")
      assert pin_row(1).icon == "hero-cog-6-tooth"

      # Identity URL still gets its cross-system hash repaired.
      assert pin_row(2).url == "/admin/system/database-queries/monthly-sales"
      assert pin_row(2).url_hash == Pin.hash_url("/admin/system/database-queries/monthly-sales")
      assert pin_row(2).icon == "hero-chart-bar-solid"

      # The dead pin keeps its URL and hash, but its icon is still repaired:
      # a pin nobody can follow is still rendered in the sidebar.
      assert pin_row(3) == %{
               url: "/people/leave/approvals",
               url_hash: Pin.hash_url("belimbing-stale-3"),
               icon: "hero-clock"
             }

      assert Enum.any?(pins.residue, fn entry ->
               entry.pin_id == 3 and entry.user_email == "ada@example.com" and
                 entry.label == "Leave approvals" and entry.url == "/people/leave/approvals" and
                 entry.reason == {:no_bilimbi_route}
             end)

      # Collision: lower sort_order wins; the loser keeps its original URL
      # and hash, and its icon is repaired in place too.
      assert pin_row(4).url == "/companies/5"

      assert pin_row(5) == %{
               url: "/companies/5",
               url_hash: Pin.hash_url("belimbing-stale-5"),
               icon: "hero-building-office-2"
             }

      assert Enum.any?(pins.residue, fn entry ->
               entry.pin_id == 5 and entry.reason == {:duplicate_of, 4}
             end)

      # NULL icon survives a hash-only repair.
      assert pin_row(6).url_hash == Pin.hash_url("/dashboard")
      assert pin_row(6).icon == nil

      # Every heroicon moved, including the two on unmapped pins; the icons
      # left alone are reported rather than guessed.
      assert pins.icons_changed == 6
      remainder_icons = Enum.map(pins.remainder, & &1.icon)
      assert nil in remainder_icons
      assert "hero-plus" in remainder_icons
      assert pin_row(7).icon == "hero-plus"
    end

    test "rerunning is idempotent and never double-applies" do
      assert {:ok, first} = run_cutover()
      assert first.steps.pins.changed > 0
      assert first.steps.pins.icons_changed > 0

      assert {:ok, second} = run_cutover()
      assert second.steps.pins.changed == 0
      assert second.steps.pins.icons_changed == 0
      assert second.steps.query_icons.changed == 0
      assert second.steps.notifications.changed == 0
      assert length(second.steps.pins.residue) == length(first.steps.pins.residue)
      assert second.steps.grants.undeclared == first.steps.grants.undeclared
    end

    test "dry_run reports without writing", %{nids: nids} do
      assert {:ok, report} = run_cutover(dry_run: true)
      assert report.dry_run
      assert report.steps.pins.changed == 5
      assert report.steps.pins.icons_changed == 6
      assert report.steps.notifications.changed == 1

      assert pin_row(1).url == "/admin/companies"
      assert pin_row(1).url_hash == Pin.hash_url("belimbing-stale-1")
      assert pin_row(3).icon == "heroicon-o-clock"
      assert query_icon(1) == "heroicon-o-table-cells"
      assert notification_url(nids["n1"]) == "/admin/companies/5"
    end

    test "remaps query icons and reports the remainder without guessing" do
      assert {:ok, report} = run_cutover()
      step = report.steps.query_icons

      assert step.examined == 4
      assert step.changed == 1
      assert step.unmapped == 3
      assert query_icon(1) == "hero-table-cells"
      assert query_icon(2) == nil
      assert query_icon(3) == "custom-svg-thing"

      remainder_icons = Enum.map(step.remainder, & &1.icon)
      assert nil in remainder_icons
      assert "custom-svg-thing" in remainder_icons
      assert "hero-magnifying-glass" in remainder_icons
    end

    test "remaps notification admin URLs and leaves the rest alone", %{nids: nids} do
      assert {:ok, report} = run_cutover()
      step = report.steps.notifications

      assert step.examined == 6
      assert step.changed == 1
      assert step.unchanged == 3
      assert step.unmapped == 2

      assert notification_url(nids["n1"]) == "/companies/5"
      assert Jason.decode!(notification_data(nids["n1"]))["title"] == "Monthly sales"
      assert notification_url(nids["n2"]) == "/dashboard"
      assert notification_url(nids["n3"]) == "https://example.com/x"
      assert is_nil(Jason.decode!(notification_data(nids["n6"]))["url"])

      assert Enum.any?(
               step.residue,
               &(&1.notification_id == nids["n4"] and &1.reason == {:no_bilimbi_route})
             )

      assert Enum.any?(
               step.residue,
               &(&1.notification_id == nids["n5"] and match?({:invalid_data, _}, &1.reason))
             )

      assert notification_data(nids["n5"]) == "not json{{{"
    end

    test "reports undeclared-capability grants without mutating them" do
      before_roles =
        SQL.query!(Repo, "SELECT * FROM base_authz_role_capabilities ORDER BY id", []).rows

      before_principals =
        SQL.query!(Repo, "SELECT * FROM base_authz_principal_capabilities ORDER BY id", []).rows

      assert {:ok, report} = run_cutover()

      grants = report.steps.grants
      assert grants.undeclared == 3

      assert Enum.any?(grants.role_grants, fn grant ->
               grant.role_id == 2 and grant.capability == "people.leave.approve"
             end)

      # Evaluation compares capability keys exactly, so a stored case variant
      # of a declared key is a permanent silent denial: report it, never
      # excuse it as declared.
      assert Enum.any?(grants.role_grants, fn grant ->
               grant.role_id == 2 and grant.capability == "ADMIN.USER.VIEW"
             end)

      assert Enum.any?(grants.principal_grants, fn grant ->
               grant.principal_type == "user" and grant.principal_id == 91 and
                 grant.capability == "commerce.order.approve" and grant.allowed == false
             end)

      assert SQL.query!(Repo, "SELECT * FROM base_authz_role_capabilities ORDER BY id", []).rows ==
               before_roles

      assert SQL.query!(Repo, "SELECT * FROM base_authz_principal_capabilities ORDER BY id", []).rows ==
               before_principals
    end

    test "a dead pin still reserves its hash for later pins" do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      target_hash = Pin.hash_url("/companies/5")

      SQL.query!(
        Repo,
        "INSERT INTO user_pins (id, user_id, label, url, url_hash, icon, sort_order, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)",
        [90, 91, "Dead early", "/people/early", target_hash, nil, -1, now, now]
      )

      assert {:ok, report} = run_cutover()

      # Pin 4 would map onto /companies/5, but the dead pin got there first
      # and keeps it; pin 4 keeps its original Belimbing URL and hash, with
      # only its icon repaired.
      assert pin_row(4) == %{
               url: "/admin/companies/5",
               url_hash: Pin.hash_url("belimbing-stale-4"),
               icon: "hero-building-office-2"
             }

      assert Enum.any?(report.steps.pins.residue, fn entry ->
               entry.pin_id == 4 and entry.reason == {:duplicate_of, 90}
             end)
    end

    test "a pin that loses a collision the database catches still has its icon repaired" do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      SQL.query!(
        Repo,
        "INSERT INTO user_pins (id, user_id, label, url, url_hash, icon, sort_order, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)",
        [90, 91, "Dead late", "/people/late", Pin.hash_url("/companies/5"), nil, 99, now, now]
      )

      assert {:ok, report} = run_cutover()

      # The dead pin sorts last, so pin 4 is examined while nothing in memory
      # holds that hash yet and the unique index is what rejects the write.
      assert pin_row(4) == %{
               url: "/admin/companies/5",
               url_hash: Pin.hash_url("belimbing-stale-4"),
               icon: "hero-building-office-2"
             }

      assert Enum.any?(report.steps.pins.residue, fn entry ->
               entry.pin_id == 4 and entry.reason == {:duplicate_of, 90}
             end)

      assert Enum.any?(report.steps.pins.residue, fn entry ->
               entry.pin_id == 5 and entry.reason == {:duplicate_of, 90}
             end)
    end

    test "a pin needing only its icon repaired is not counted as a URL change" do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      SQL.query!(
        Repo,
        "INSERT INTO user_pins (id, user_id, label, url, url_hash, icon, sort_order, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)",
        [
          93,
          92,
          "Notifications",
          "/notifications",
          Pin.hash_url("/notifications"),
          "heroicon-o-bell",
          9,
          now,
          now
        ]
      )

      assert {:ok, report} = run_cutover()
      pins = report.steps.pins

      assert pins.examined == 9
      assert pins.changed == 5
      assert pins.unchanged == 2
      assert pins.icons_changed == 7

      assert pin_row(93) == %{
               url: "/notifications",
               url_hash: Pin.hash_url("/notifications"),
               icon: "hero-bell"
             }
    end

    test "remaps every notification past the first read batch" do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      SQL.query!(
        Repo,
        """
        INSERT INTO notifications (id, type, notifiable_type, notifiable_id, data, created_at, updated_at)
        SELECT gen_random_uuid(), $1, $2, $3, $4, $5, $5 FROM generate_series(1, 600)
        """,
        [
          "generic",
          "App\\Core\\User\\Models\\User",
          91,
          Jason.encode!(%{"title" => "Bulk", "url" => "/admin/companies"}),
          now
        ]
      )

      assert {:ok, report} = run_cutover()
      step = report.steps.notifications

      assert step.examined == 606
      assert step.changed == 601

      assert notification_count("%\"url\":\"/companies\"%") == 600
      assert notification_count("%/admin/companies%") == 0
    end

    test "a NULL url becomes residue instead of aborting the run" do
      SQL.query!(Repo, "ALTER TABLE user_pins ALTER COLUMN url DROP NOT NULL", [])

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      SQL.query!(
        Repo,
        "INSERT INTO user_pins (id, user_id, label, url, url_hash, icon, sort_order, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)",
        [91, 91, "Null url", nil, Pin.hash_url("belimbing-stale-91"), nil, 99, now, now]
      )

      assert {:ok, report} = run_cutover()

      assert Enum.any?(report.steps.pins.residue, fn entry ->
               entry.pin_id == 91 and match?({:invalid_row, _}, entry.reason)
             end)

      assert report.steps.pins.changed == 5
    end

    test "says so loudly when a required table is absent" do
      SQL.query!(Repo, "DROP TABLE IF EXISTS user_pins", [])

      assert {:error, message} = run_cutover()
      assert message =~ "user_pins"
      assert message =~ "bilimbi.schema.adopt"
    end

    test "reads only the schema the prefix names" do
      assert {:error, message} = run_cutover(prefix: "bilimbi_cutover_absent_schema")
      assert message =~ "bilimbi_cutover_absent_schema"
      assert message =~ "user_pins"
    end

    test "mix task dry-run names every kept-broken pin and writes nothing" do
      Mix.Task.reenable("bilimbi.cutover.remap")
      Mix.shell(Mix.Shell.Process)

      try do
        Mix.Task.run("bilimbi.cutover.remap", ["--dry-run", "--prefix", "pg_temp"])
      after
        Mix.shell(Mix.Shell.IO)
      end

      assert pin_row(1).url == "/admin/companies"

      messages = shell_messages()

      assert "user_pins: examined=8 changed=5 unchanged=1 unmapped=2 icons_changed=6" in messages

      assert Enum.any?(messages, fn message ->
               message =~ "ada@example.com" and message =~ "Leave approvals" and
                 message =~ "/people/leave/approvals"
             end)
    end

    test "mix task reports grants without a deployment application running" do
      ContributionRegistry.clear_for_test!()
      on_exit(fn -> ContributionRegistry.install!() end)

      Mix.Task.reenable("bilimbi.cutover.remap")
      Mix.shell(Mix.Shell.Process)

      try do
        Mix.Task.run("bilimbi.cutover.remap", ["--dry-run", "--prefix", "pg_temp"])
      after
        Mix.shell(Mix.Shell.IO)
      end

      messages = shell_messages()

      assert Enum.any?(messages, &String.starts_with?(&1, "authz grants (report only"))

      assert Enum.any?(messages, fn message ->
               message =~ "UNDECLARED" and message =~ "people.leave.approve"
             end)
    end
  end

  # The grants step reads the live Authz registry by default; tests inject the
  # declared set so they do not depend on a deployment snapshot. Fixtures are
  # temporary tables, so the run is pointed at the session schema that holds
  # them rather than the migrated `public` one.
  @declared_capabilities ["admin.company.list", "admin.user.view"]

  defp run_cutover(opts \\ []) do
    [prefix: "pg_temp", declared_capabilities: @declared_capabilities]
    |> Keyword.merge(opts)
    |> Cutover.run()
  end

  defp seed_pins! do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows = [
      {1, 91, 0, "Companies", "/admin/companies", "heroicon-o-cog-6-tooth"},
      {2, 91, 1, "Monthly sales", "/admin/system/database-queries/monthly-sales",
       "heroicon-s-chart-bar"},
      {3, 91, 2, "Leave approvals", "/people/leave/approvals", "heroicon-o-clock"},
      {4, 91, 3, "Companies five", "/admin/companies/5", "heroicon-o-building-office-2"},
      {5, 91, 4, "Companies five again", "/companies/5", "heroicon-o-building-office-2"},
      {6, 91, 5, "Dashboard", "/dashboard", nil},
      {7, 92, 0, "Users", "/users/new", "hero-plus"},
      {8, 92, 1, "New employee", "/admin/employees/create", "heroicon-m-user-plus"}
    ]

    Enum.each(rows, fn {id, user_id, sort, label, url, icon} ->
      # Every Belimbing row carries its own hash; only pin 7 already holds
      # the Bilimbi-canonical one. Distinct stale hashes also keep the seed
      # itself clear of the unique constraint under test.
      hash = if id == 7, do: Pin.hash_url(url), else: Pin.hash_url("belimbing-stale-#{id}")

      SQL.query!(
        Repo,
        "INSERT INTO user_pins (id, user_id, label, url, url_hash, icon, sort_order, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)",
        [id, user_id, label, url, hash, icon, sort, now, now]
      )
    end)
  end

  defp seed_queries! do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows = [
      {1, 91, "Sales", "sales", "heroicon-o-table-cells"},
      {2, 91, "No icon", "no-icon", nil},
      {3, 91, "Custom", "custom", "custom-svg-thing"},
      {4, 92, "Good already", "good", "hero-magnifying-glass"}
    ]

    Enum.each(rows, fn {id, user_id, name, slug, icon} ->
      SQL.query!(
        Repo,
        "INSERT INTO user_database_queries (id, user_id, name, slug, sql_query, icon, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)",
        [id, user_id, name, slug, "SELECT 1", icon, now, now]
      )
    end)
  end

  defp seed_notifications! do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows = [
      {"n1", %{"title" => "Monthly sales", "url" => "/admin/companies/5"}},
      {"n2", %{"title" => "Hi", "url" => "/dashboard"}},
      {"n3", %{"title" => "Hi", "url" => "https://example.com/x"}},
      {"n4", %{"title" => "Hi", "url" => "/people/inbox"}},
      {"n5", "not json{{{"},
      {"n6", %{"title" => "No url here"}}
    ]

    Map.new(rows, fn {key, data} ->
      id = Ecto.UUID.generate()
      payload = if is_map(data), do: Jason.encode!(data), else: data

      SQL.query!(
        Repo,
        "INSERT INTO notifications (id, type, notifiable_type, notifiable_id, data, created_at, updated_at) VALUES ($1::uuid,$2,$3,$4,$5,$6,$7)",
        [Ecto.UUID.dump!(id), "generic", "App\\Core\\User\\Models\\User", 91, payload, now, now]
      )

      {key, id}
    end)
  end

  defp seed_grants! do
    SQL.query!(
      Repo,
      "INSERT INTO base_authz_roles (id, company_id, name, code, is_system, grant_all) VALUES (1,NULL,'Core admin','core_admin',true,true)",
      []
    )

    SQL.query!(
      Repo,
      "INSERT INTO base_authz_roles (id, company_id, name, code, is_system, grant_all) VALUES (2,73,'Manager','manager',false,false)",
      []
    )

    SQL.query!(
      Repo,
      "INSERT INTO base_authz_role_capabilities (role_id, capability_key) VALUES (1,'admin.company.list')",
      []
    )

    SQL.query!(
      Repo,
      "INSERT INTO base_authz_role_capabilities (role_id, capability_key) VALUES (2,'people.leave.approve')",
      []
    )

    SQL.query!(
      Repo,
      "INSERT INTO base_authz_role_capabilities (role_id, capability_key) VALUES (2,'ADMIN.USER.VIEW')",
      []
    )

    SQL.query!(
      Repo,
      "INSERT INTO base_authz_principal_capabilities (company_id, principal_type, principal_id, capability_key, is_allowed) VALUES (73,'user',91,'admin.company.list',true)",
      []
    )

    SQL.query!(
      Repo,
      "INSERT INTO base_authz_principal_capabilities (company_id, principal_type, principal_id, capability_key, is_allowed) VALUES (73,'user',91,'commerce.order.approve',false)",
      []
    )
  end

  defp shell_messages(acc \\ []) do
    receive do
      {:mix_shell, :info, [message]} -> shell_messages([message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp pin_row(id) do
    %{rows: [[url, url_hash, icon]]} =
      SQL.query!(Repo, "SELECT url, url_hash, icon FROM user_pins WHERE id = $1", [id])

    %{url: url, url_hash: url_hash, icon: icon}
  end

  defp query_icon(id) do
    %{rows: [[icon]]} =
      SQL.query!(Repo, "SELECT icon FROM user_database_queries WHERE id = $1", [id])

    icon
  end

  defp notification_data(id) do
    %{rows: [[data]]} =
      SQL.query!(Repo, "SELECT data FROM notifications WHERE id = $1::uuid", [Ecto.UUID.dump!(id)])

    data
  end

  defp notification_count(pattern) do
    %{rows: [[count]]} =
      SQL.query!(Repo, "SELECT count(*) FROM notifications WHERE data LIKE $1", [pattern])

    count
  end

  defp notification_url(id), do: Jason.decode!(notification_data(id))["url"]
end
