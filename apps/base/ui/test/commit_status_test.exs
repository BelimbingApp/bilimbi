defmodule Bilimbi.Base.UI.CommitStatusTest do
  @moduledoc """
  The per-fact commit bookkeeping behind `<.inline_edit>` and
  `<.commit_status>`, covered on its own rather than only through the pages
  that adopt it.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.CommitStatus
  alias Phoenix.LiveView.Socket

  # A bare socket with the flash LiveView mounts, and nothing to report yet.
  defp socket do
    CommitStatus.init(%Socket{assigns: %{__changed__: %{}, flash: %{}}})
  end

  defp statuses(socket), do: socket.assigns.field_status

  describe "init/1" do
    test "starts with nothing to report on any fact" do
      assert statuses(socket()) == %{}
    end
  end

  describe "put/3" do
    test "records the outcome on the fact that made the commit" do
      socket = CommitStatus.put(socket(), "name", :saved)
      assert statuses(socket) == %{"name" => :saved}

      socket = CommitStatus.put(socket, "email", {:error, "refused"})
      assert statuses(socket)["email"] == {:error, "refused"}
    end

    test "Saved belongs to the most recent commit only, whatever its outcome" do
      saved = CommitStatus.put(socket(), "name", :saved)

      assert statuses(CommitStatus.put(saved, "email", :saved)) == %{"email" => :saved}

      assert statuses(CommitStatus.put(saved, "email", {:error, "refused"})) ==
               %{"email" => {:error, "refused"}}

      assert statuses(CommitStatus.put(saved, "location", nil)) == %{"location" => nil}
    end

    test "a success elsewhere never clears another fact's refusal" do
      socket =
        socket()
        |> CommitStatus.put("email", {:error, "refused"})
        |> CommitStatus.put("name", :saved)

      assert statuses(socket) == %{"email" => {:error, "refused"}, "name" => :saved}
    end

    test "a refusal stays until that fact is committed again" do
      socket =
        socket()
        |> CommitStatus.put("email", {:error, "first"})
        |> CommitStatus.put("email", {:error, "second"})

      assert statuses(socket) == %{"email" => {:error, "second"}}

      assert statuses(CommitStatus.put(socket, "email", :saved)) == %{"email" => :saved}
    end

    test "refuses a status outside the vocabulary" do
      assert_raise ArgumentError, ~r/status must be nil, :saved, or \{:error, message\}/, fn ->
        CommitStatus.put(socket(), "name", :stored)
      end

      assert_raise ArgumentError, fn ->
        CommitStatus.put(socket(), "name", {:error, :atom})
      end
    end
  end

  describe "write_forbidden/2" do
    test "drops every Saved, keeps refusals and reports through the error flash" do
      socket =
        socket()
        |> CommitStatus.put("name", :saved)
        |> CommitStatus.put("email", {:error, "refused"})
        |> CommitStatus.put("phone", :saved)
        |> CommitStatus.write_forbidden("You do not have permission to edit widgets.")

      assert statuses(socket) == %{"email" => {:error, "refused"}}
      assert socket.assigns.flash == %{"error" => "You do not have permission to edit widgets."}
    end
  end

  describe "inline_field/2" do
    @fields %{"name" => :name, "email" => :email}

    test "resolves a declared name carrying a string value" do
      assert CommitStatus.inline_field(%{"id" => "7", "email" => "a@b.c"}, @fields) ==
               {:ok, "email", :email, "a@b.c"}
    end

    test "ignores names the page did not declare" do
      assert CommitStatus.inline_field(%{"id" => "7", "role" => "admin"}, @fields) == :error
    end

    test "ignores a declared name whose value is not a string" do
      assert CommitStatus.inline_field(%{"name" => ["x"]}, @fields) == :error
      assert CommitStatus.inline_field(%{"name" => nil}, @fields) == :error
    end

    test "ignores params that are not a map" do
      assert CommitStatus.inline_field("name=x", @fields) == :error
      assert CommitStatus.inline_field(nil, @fields) == :error
    end
  end

  describe "refusal_message/4" do
    test "names the rejected value, the fact and every reason for its field" do
      errors = [
        email: {"must be an email address", [validation: :format]},
        email: {"has already been taken", [constraint: :unique]},
        name: {"can't be blank", [validation: :required]}
      ]

      assert CommitStatus.refusal_message("Email", :email, "bad", errors) ==
               "\"bad\" was not saved: Email must be an email address, has already been taken."
    end

    test "says the fact could not be saved when the changeset names no reason for it" do
      assert CommitStatus.refusal_message("Label", :label, "HQ", name: {"is odd", []}) ==
               "\"HQ\" was not saved: Label could not be saved."
    end

    test "interpolates translated error options" do
      errors = [
        phone: {"should be at most %{count} character(s)", [count: 32, validation: :length]}
      ]

      assert CommitStatus.refusal_message("Phone", :phone, "1", errors) ==
               "\"1\" was not saved: Phone should be at most 32 character(s)."
    end

    test "repeats only the truncated rejected value" do
      long = String.duplicate("a", 61)

      assert CommitStatus.refusal_message("Label", :label, long, []) ==
               "\"#{String.duplicate("a", 60)}…\" was not saved: Label could not be saved."
    end
  end

  describe "rejected_value/1" do
    test "trims the value and keeps one of at most 60 characters whole" do
      sixty = String.duplicate("x", 60)

      assert CommitStatus.rejected_value("  #{sixty}  ") == sixty
      assert CommitStatus.rejected_value(sixty) == sixty
    end

    test "cuts a longer value at 60 characters and marks the cut with an ellipsis" do
      sixty = String.duplicate("x", 60)

      assert CommitStatus.rejected_value(sixty <> "y") == sixty <> "…"

      assert CommitStatus.rejected_value(String.duplicate("é", 70)) ==
               String.duplicate("é", 60) <> "…"
    end

    test "names a value that is not a string as it prints" do
      assert CommitStatus.rejected_value(42) == "42"
      assert CommitStatus.rejected_value(nil) == ""
    end
  end

  describe "failure_message/0" do
    test "is the generic sentence for a reason the page has no noun for" do
      assert CommitStatus.failure_message() ==
               "The change was not saved. Try again, and tell your administrator if it keeps failing."
    end
  end

  describe "normalize/1" do
    test "passes the vocabulary through unchanged" do
      assert CommitStatus.normalize(nil) == nil
      assert CommitStatus.normalize(:saved) == :saved
      assert CommitStatus.normalize({:error, "why"}) == {:error, "why"}
    end

    test "raises for anything else" do
      assert_raise ArgumentError, fn -> CommitStatus.normalize(:error) end
      assert_raise ArgumentError, fn -> CommitStatus.normalize({:error, nil}) end
      assert_raise ArgumentError, fn -> CommitStatus.normalize("saved") end
    end
  end
end
