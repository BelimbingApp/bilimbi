defmodule Bilimbi.Base.UI.WorkspaceTest do
  @moduledoc """
  The follow channel's contract on the page side: the token and its URL
  forms, the topic an account may reach, the mount hook that joins a page
  to its workspace, and the facts a page announces.
  """

  use ExUnit.Case, async: false

  alias Bilimbi.Base.UI.Workspace
  alias Phoenix.LiveView.Lifecycle
  alias Phoenix.LiveView.Socket

  @token "abcdefghijklmnop"
  @scope %{scope: %{tenant: %{id: 41}}, user: %{"user_id" => 91}}
  @pubsub Application.compile_env!(:bilimbi_base_ui, :pubsub_server)

  setup do
    # The channel rides the host's PubSub, which this package does not start.
    start_supervised!({Phoenix.PubSub, name: @pubsub})
    :ok
  end

  # A socket the way LiveView hands one to `on_mount`: with the lifecycle
  # `attach_hook` writes into, connected when it has a transport.
  defp socket(assigns, connected?) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{lifecycle: %Lifecycle{}, live_temp: %{}},
      transport_pid: if(connected?, do: self())
    }
  end

  describe "the token" do
    test "is derived from the host's LiveView id and has one shape" do
      token = Workspace.host_token("phx-GAcfs2nFBAnkKAHB")

      assert token == Workspace.host_token("phx-GAcfs2nFBAnkKAHB")
      assert token != Workspace.host_token("phx-other")
      assert Workspace.token?(token)
      refute Workspace.token?("short")
      refute Workspace.token?(String.duplicate("a", 17))
      refute Workspace.token?("abcdefghijklmno/")
      refute Workspace.token?(nil)
    end

    test "joins and leaves a frame's URL without touching the page's own query" do
      assert Workspace.frame_url("/companies", @token) == "/companies?ws=#{@token}"

      assert Workspace.frame_url("/companies?page=2&q=a%20b", @token) ==
               "/companies?page=2&q=a+b&ws=#{@token}"

      assert Workspace.strip_token("/companies?page=2&ws=#{@token}") == "/companies?page=2"
      assert Workspace.strip_token("/companies?ws=#{@token}") == "/companies"
      assert Workspace.strip_token("/companies") == "/companies"
    end

    test "enters the LiveView session only with a well-formed token" do
      conn = Plug.Test.init_test_session(%Plug.Conn{query_string: "ws=#{@token}"}, %{})
      assert Workspace.session(conn) == %{"bilimbi_workspace" => @token}

      assert Workspace.session(%Plug.Conn{query_string: "ws=nope"}) == %{}
      assert Workspace.session(%Plug.Conn{query_string: ""}) == %{}
    end
  end

  describe "the topic" do
    test "names the account and the token" do
      assert Workspace.topic(41, 91, @token) == "workspace:41:91:#{@token}"
      assert Workspace.topic_for(@scope, @token) == "workspace:41:91:#{@token}"
      assert Workspace.topic_for(%{scope: %{tenant: %{id: 41}}}, @token) == nil
      assert Workspace.topic_for(nil, @token) == nil
    end
  end

  describe "on_mount/4" do
    test "outside a workspace the page gets no channel" do
      assert {:cont, socket} =
               Workspace.on_mount(:attach, %{}, %{}, socket(%{current_scope: @scope}, true))

      assert socket.assigns.workspace == nil

      assert {:cont, socket} =
               Workspace.on_mount(
                 :attach,
                 %{},
                 %{"bilimbi_workspace" => "bad"},
                 socket(%{current_scope: @scope}, true)
               )

      assert socket.assigns.workspace == nil

      assert {:cont, socket} =
               Workspace.on_mount(
                 :attach,
                 %{},
                 %{"bilimbi_workspace" => @token},
                 socket(%{current_scope: nil}, true)
               )

      assert socket.assigns.workspace == nil
    end

    test "a connected page joins its workspace, learns what is followed, and answers a selection" do
      # The hook subscribes this process, the page's own, so every message on
      # the topic lands here once.
      topic = Workspace.topic(41, 91, @token)

      assert {:cont, socket} =
               Workspace.on_mount(
                 :attach,
                 %{},
                 %{"bilimbi_workspace" => @token},
                 socket(%{current_scope: @scope}, true)
               )

      assert %{token: @token, topic: ^topic, follows: []} = socket.assigns.workspace
      assert_receive {:workspace_joined}

      # The host says which kinds are followed; the page keeps them.
      :ok = Workspace.broadcast(topic, {:workspace_follows, ["core/company", "bad kind"]})
      assert_receive {:workspace_follows, _} = message
      assert {:halt, socket} = run_hook(socket, :handle_info, [message])
      assert socket.assigns.workspace.follows == ["core/company"]
      assert Workspace.followed?(socket.assigns.workspace, "core/company")
      refute Workspace.followed?(socket.assigns.workspace, "core/user")

      # A row selection is announced as a fact and goes no further.
      assert {:halt, ^socket} =
               run_hook(socket, :handle_event, [
                 "workspace:select",
                 %{"kind" => "core/company", "id" => "42"}
               ])

      assert_receive {:workspace_fact, %{kind: "core/company", id: "42"}}

      assert {:halt, ^socket} =
               run_hook(socket, :handle_event, [
                 "workspace:select",
                 %{"kind" => "x", "id" => "42"}
               ])

      refute_receive {:workspace_fact, _}

      assert {:cont, ^socket} = run_hook(socket, :handle_event, ["other", %{}])
    end

    test "a disconnected render joins nothing but still knows its workspace" do
      topic = Workspace.topic(41, 91, @token)
      :ok = Workspace.subscribe(topic)

      assert {:cont, socket} =
               Workspace.on_mount(
                 :attach,
                 %{},
                 %{"bilimbi_workspace" => @token},
                 socket(%{current_scope: @scope}, false)
               )

      assert socket.assigns.workspace.topic == topic
      refute_receive {:workspace_joined}

      # Nor does it announce: the connected mount will.
      Workspace.announce(socket, %{kind: "core/company", id: 42})
      refute_receive {:workspace_fact, _}
    end
  end

  describe "announce/2" do
    test "sends a well-formed fact to the workspace and nothing else" do
      topic = Workspace.topic(41, 91, @token)
      :ok = Workspace.subscribe(topic)
      workspace = %{token: @token, topic: topic, follows: []}
      socket = socket(%{current_scope: @scope, workspace: workspace}, true)

      assert ^socket = Workspace.announce(socket, %{kind: "core/company", id: 42})
      assert_receive {:workspace_fact, %{kind: "core/company", id: 42}}

      for bad <- [
            %{kind: "Core/Company", id: 42},
            %{kind: "core/company", id: 0},
            %{kind: "core/company", id: ""},
            %{kind: "core/company", id: "4/2"},
            %{kind: "core/company", id: nil}
          ] do
        Workspace.announce(socket, bad)
      end

      refute_receive {:workspace_fact, _}

      alone = socket(%{current_scope: @scope, workspace: nil}, true)
      assert ^alone = Workspace.announce(alone, %{kind: "core/company", id: 42})
      refute_receive {:workspace_fact, _}
    end
  end

  test "a missing PubSub server silences the channel rather than crashing the page" do
    Application.put_env(:bilimbi_base_ui, :pubsub_server, Bilimbi.Base.UI.NoSuchPubSub)
    on_exit(fn -> Application.put_env(:bilimbi_base_ui, :pubsub_server, @pubsub) end)
    topic = Workspace.topic(41, 91, @token)

    assert Workspace.subscribe(topic) == {:error, :pubsub_unavailable}
    assert Workspace.broadcast(topic, {:workspace_joined}) == {:error, :pubsub_unavailable}
  end

  # Runs the hooks `on_mount/4` attached, the way LiveView does.
  defp run_hook(socket, stage, args) do
    socket.private.lifecycle
    |> Map.fetch!(stage)
    |> Enum.reduce_while({:cont, socket}, fn %{function: fun}, {:cont, socket} ->
      case apply(fun, args ++ [socket]) do
        {:cont, socket} -> {:cont, {:cont, socket}}
        {:halt, socket} -> {:halt, {:halt, socket}}
        {:halt, _reply, socket} -> {:halt, {:halt, socket}}
      end
    end)
  end
end
