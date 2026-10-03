defmodule Bilimbi.Base.UI.SessionGuard do
  @moduledoc """
  Invokes the host's process-local authentication guard before component work.

  The authenticated Web mount installs a callback shared by every component
  in that LiveView process. Events count as activity; updates and asynchronous
  results only validate access. Public LiveViews install no guard.
  """

  def install(guard) when is_function(guard, 1), do: Process.put(__MODULE__, guard)

  def allowed?(activity?) do
    case Process.get(__MODULE__) do
      nil -> true
      guard -> guard.(activity?)
    end
  end

  defmacro __using__(_opts) do
    quote do
      @before_compile Bilimbi.Base.UI.SessionGuard
    end
  end

  defmacro __before_compile__(env) do
    for {name, arity, activity?, result} <- [
          {:handle_event, 3, true, :noreply},
          {:update, 2, false, :ok},
          {:handle_async, 3, false, :noreply}
        ],
        Module.defines?(env.module, {name, arity}, :def) do
      args = Macro.generate_arguments(arity - 1, __MODULE__)

      denied_socket =
        if name == :update do
          quote do: Phoenix.Component.assign(socket, unquote(hd(args)))
        else
          quote do: socket
        end

      quote do
        defoverridable [{unquote(name), unquote(arity)}]

        def unquote(name)(unquote_splicing(args), socket) do
          if Bilimbi.Base.UI.SessionGuard.allowed?(unquote(activity?)) do
            super(unquote_splicing(args), socket)
          else
            send(self(), :durable_session_expired)
            {unquote(result), unquote(denied_socket)}
          end
        end
      end
    end
  end
end
