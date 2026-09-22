defmodule BilimbiWeb.EndpointTransportTest do
  use ExUnit.Case, async: true

  test "fallback polls retain session authentication without compiling every request" do
    {"/live", Phoenix.LiveView.Socket, options} =
      Enum.find(BilimbiWeb.Endpoint.__sockets__(), fn {path, _, _} -> path == "/live" end)

    assert options[:longpoll][:code_reloader] == false

    assert options[:longpoll][:connect_info][:session] ==
             options[:websocket][:connect_info][:session]

    assert options[:longpoll][:connect_info][:session][:store] == :cookie
  end
end
