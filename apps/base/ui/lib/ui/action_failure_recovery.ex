defmodule Bilimbi.Base.UI.ActionFailureRecovery do
  @moduledoc """
  Recovers unexpected LiveView action failures without hiding deliberate outcomes.

  Phoenix lifecycle hooks run before a view or component's `handle_event/3`
  callback, so they cannot rescue a failure raised by that callback. This
  compile-time wrapper surrounds the completed callback instead. Rendering and
  every other lifecycle callback remain outside the recovery boundary.
  """

  require Logger

  @message "That action did not finish. The error has been recorded — if it keeps happening, tell your administrator."

  @outcome_exceptions [
    "Elixir.Bilimbi.Base.Authz.AuthorizationDeniedError",
    "Elixir.Ecto.InvalidChangesetError",
    "Elixir.Ecto.NoResultsError"
  ]

  @component_failure_message {__MODULE__, :component_failure}

  defmacro __using__(kind) when kind in [:live_view, :live_component] do
    quote do
      @bilimbi_action_failure_kind unquote(kind)
      @before_compile Bilimbi.Base.UI.ActionFailureRecovery

      if unquote(kind) == :live_view do
        Phoenix.LiveView.on_mount(Bilimbi.Base.UI.ActionFailureRecovery)
      end
    end
  end

  defmacro __before_compile__(env) do
    if Module.defines?(env.module, {:handle_event, 3}, :def) do
      kind = Module.get_attribute(env.module, :bilimbi_action_failure_kind)

      quote do
        defoverridable handle_event: 3

        def handle_event(event, params, socket) do
          super(event, params, socket)
        rescue
          exception ->
            Bilimbi.Base.UI.ActionFailureRecovery.recover(
              exception,
              __STACKTRACE__,
              socket,
              unquote(kind)
            )
        end
      end
    else
      quote do
      end
    end
  end

  @doc false
  def on_mount(:default, _params, _session, socket) do
    socket =
      Phoenix.LiveView.attach_hook(
        socket,
        __MODULE__,
        :handle_info,
        &handle_info/2
      )

    {:cont, socket}
  end

  @doc false
  def handle_info(@component_failure_message, socket) do
    {:halt, Phoenix.LiveView.put_flash(socket, :error, @message)}
  end

  def handle_info(_message, socket), do: {:cont, socket}

  @doc false
  @spec recover(
          Exception.t(),
          Exception.stacktrace(),
          Phoenix.LiveView.Socket.t(),
          :live_view | :live_component
        ) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def recover(exception, stacktrace, socket, kind) do
    if exception.__struct__ |> Atom.to_string() |> Kernel.in(@outcome_exceptions) do
      reraise exception, stacktrace
    end

    Logger.error(Exception.format(:error, exception, stacktrace))

    recover_socket(socket, kind)
  end

  defp recover_socket(socket, :live_view) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :error, @message)}
  end

  defp recover_socket(socket, :live_component) do
    send(self(), @component_failure_message)
    {:noreply, socket}
  end
end
