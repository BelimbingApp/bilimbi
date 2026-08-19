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

  test "counts stored sessions without reading payloads" do
    assert Session.count_sessions() == 0

    put_session!("older", 100, "10.0.0.1", "Firefox")
    put_session!("newer", 300, "10.0.0.2", "Phoenix mobile")

    assert Session.count_sessions() == 2
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

  test "terminates multiple sessions for one user without reading or returning payloads" do
    put_user_session!("current", 41, "current opaque payload")
    put_user_session!("other-a", 41, "first opaque payload")
    put_user_session!("other-b", 41, "second opaque payload")
    put_user_session!("another-user", 42, "another user's opaque payload")
    put_session!("anonymous", 100)

    assert {:ok, 2} = Session.terminate_user_sessions(41, "current")

    assert {:ok, %Entry{id: "current"}} = Session.fetch_session("current")
    assert {:error, :not_found} = Session.fetch_session("other-a")
    assert {:error, :not_found} = Session.fetch_session("other-b")
    assert {:ok, %Entry{id: "another-user"}} = Session.fetch_session("another-user")
    assert {:ok, %Entry{id: "anonymous", user_id: nil}} = Session.fetch_session("anonymous")
  end

  test "returns the stable count when no other target session exists" do
    put_user_session!("current", 41, "opaque")

    assert {:ok, 0} = Session.terminate_user_sessions(41, "current")
    assert {:ok, 0} = Session.terminate_user_sessions(42, "current")
    assert {:ok, %Entry{id: "current"}} = Session.fetch_session("current")
  end

  test "preserves a current session belonging to another user while terminating one target session" do
    put_user_session!("target", 41, "target opaque payload")
    put_user_session!("current", 42, "current opaque payload")

    assert {:ok, 1} = Session.terminate_user_sessions(41, "current")

    assert {:error, :not_found} = Session.fetch_session("target")
    assert {:ok, %Entry{id: "current", user_id: 42}} = Session.fetch_session("current")
  end

  test "rejects malformed identifiers without widening the deletion" do
    put_user_session!("current", 41, "current opaque payload")
    put_user_session!("target", 41, "target opaque payload")

    for {user_id, current_session_id} <- [
          {0, "current"},
          {-1, "current"},
          {"41", "current"},
          {41, ""},
          {41, nil},
          {41, 42}
        ] do
      assert_raise FunctionClauseError, fn ->
        Session.terminate_user_sessions(user_id, current_session_id)
      end
    end

    assert {:ok, %Entry{id: "current"}} = Session.fetch_session("current")
    assert {:ok, %Entry{id: "target"}} = Session.fetch_session("target")
  end

  test "composes with and rolls back through a shared Repo transaction" do
    put_user_session!("current", 41, "current opaque payload")
    put_user_session!("target", 41, "target opaque payload")

    assert {:error, :rollback} =
             Repo.transaction(fn ->
               assert {:ok, 1} = Session.terminate_user_sessions(41, "current")
               Repo.rollback(:rollback)
             end)

    assert {:ok, %Entry{id: "current"}} = Session.fetch_session("current")
    assert {:ok, %Entry{id: "target"}} = Session.fetch_session("target")
  end

  test "does not prevent a later session from being established" do
    put_user_session!("current", 41, "current opaque payload")
    put_user_session!("existing", 41, "existing opaque payload")

    assert {:ok, 1} = Session.terminate_user_sessions(41, "current")
    put_user_session!("later", 41, "later opaque payload")

    assert {:error, :not_found} = Session.fetch_session("existing")
    assert {:ok, %Entry{id: "later", user_id: 41}} = Session.fetch_session("later")
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

  defp put_user_session!(id, user_id, payload) do
    {:ok, entry} =
      Session.put_session(id, payload, %{
        user_id: user_id,
        last_activity: 100
      })

    entry
  end
end
