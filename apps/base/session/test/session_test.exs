defmodule Bilimbi.Base.SessionTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Session.Contributions
  alias Bilimbi.Base.Session.Entry
  alias Bilimbi.Base.Session.Schema
  alias Bilimbi.Base.Session.Summary

  import Bilimbi.Base.Session.TestFixtures

  setup do
    create_sessions_table!()
    :ok
  end

  test "contributes the canonical operational capabilities and read roles" do
    assert %{
             authz: %{
               capabilities: [
                 "admin.system.session.list",
                 "admin.system.session.manage"
               ],
               roles: %{
                 "auditor" => %{capabilities: ["admin.system.session.list"]},
                 "system_viewer" => %{capabilities: ["admin.system.session.list"]}
               }
             }
           } = Contributions.contributions()
  end

  test "stores, fetches, and replaces an opaque session payload" do
    assert {:ok,
            %Entry{
              id: "session-a",
              user_id: 41,
              payload: "laravel-or-phoenix-opaque",
              last_activity: 100
            }} =
             Session.put_session("session-a", "laravel-or-phoenix-opaque", %{
               user_id: 41,
               ip_address: "127.0.0.1",
               user_agent: "Bilimbi test",
               last_activity: 100
             })

    assert {:ok, %Entry{payload: "laravel-or-phoenix-opaque"}} =
             Session.fetch_session("session-a")

    assert {:ok, %Entry{payload: "replacement", last_activity: 200}} =
             Session.put_session("session-a", "replacement", last_activity: 200)

    assert Repo.aggregate(Schema, :count) == 1
  end

  test "lists payload-free metadata with search, ordering, and bounds" do
    put_session!("older", 100, "10.0.0.1", "Firefox")
    put_session!("newer", 300, "10.0.0.2", "Phoenix mobile")
    put_session!("middle", 200, "192.0.2.2", "Phoenix desktop")

    assert [%Summary{id: "newer"}, %Summary{id: "middle"}] =
             Session.list_sessions(search: "Phoenix", limit: 2)

    refute Map.has_key?(hd(Session.list_sessions(limit: 1)), :payload)

    assert_raise ArgumentError, ~r/session limit must be between 1 and 500/, fn ->
      Session.list_sessions(limit: 501)
    end

    assert_raise ArgumentError, ~r/unknown keys/, fn ->
      Session.list_sessions(page: 2)
    end
  end

  test "termination protects the current session and is otherwise idempotent" do
    put_session!("current", 100)
    put_session!("other", 100)

    assert {:error, :current_session} = Session.terminate_session("current", "current")
    assert {:ok, :terminated} = Session.terminate_session("other", "current")
    assert {:ok, :not_found} = Session.terminate_session("other", "current")
    assert {:ok, %Entry{id: "current"}} = Session.fetch_session("current")

    assert :ok = Session.delete_session("current")
    assert :ok = Session.delete_session("current")
  end

  test "prunes only sessions older than the supplied activity boundary" do
    put_session!("expired", 99)
    put_session!("boundary", 100)
    put_session!("active", 101)

    assert Session.prune_expired(100) == 1
    assert Enum.map(Session.list_sessions(), & &1.id) == ["active", "boundary"]
  end

  test "validates canonical column limits and activity metadata" do
    assert {:error, changeset} =
             Session.put_session(String.duplicate("a", 256), "payload", %{
               user_id: 0,
               ip_address: String.duplicate("1", 46),
               last_activity: -1
             })

    assert Keyword.has_key?(changeset.errors, :id)
    assert Keyword.has_key?(changeset.errors, :user_id)
    assert Keyword.has_key?(changeset.errors, :ip_address)
    assert Keyword.has_key?(changeset.errors, :last_activity)
  end

  defp put_session!(id, last_activity, ip_address \\ nil, user_agent \\ nil) do
    {:ok, entry} =
      Session.put_session(id, "opaque", %{
        ip_address: ip_address,
        user_agent: user_agent,
        last_activity: last_activity
      })

    entry
  end
end
