defmodule Bilimbi.Base.UI.ComponentActivity do
  @moduledoc """
  Forwards authenticated component interactions to the owning LiveView.

  Authenticated components receive `current_scope`. Their events notify the
  host without carrying a session ID; the host resolves its own identity and
  owns session housekeeping. Callback results and failure recovery are preserved.
  """

  defmacro __using__(_opts) do
    quote do
      @before_compile Bilimbi.Base.UI.ComponentActivity
    end
  end

  defmacro __before_compile__(env) do
    if Module.defines?(env.module, {:handle_event, 3}, :def) do
      quote do
        defoverridable handle_event: 3

        def handle_event(event, params, socket) do
          Bilimbi.Base.UI.ComponentActivity.notify(socket)
          super(event, params, socket)
        end
      end
    end
  end

  @doc false
  def notify(%{assigns: %{current_scope: current_scope}}) when not is_nil(current_scope) do
    send(self(), {__MODULE__, :activity})
    :ok
  end

  def notify(_socket), do: :ok
end

