defmodule Bilimbi.Base.Authz.LiveAuthorization do
  @moduledoc """
  Re-asks Authz, inside a connected LiveView, whether the signed-in actor
  still holds a capability.

  A LiveView process outlives its mount. The grant that let the page open can
  be revoked while the page stays open, and the `current_scope.capabilities`
  list the page renders its controls from was computed at mount, so a cached
  `can_*?` assign is presentation state, not authority. The host re-checks
  the route's declared capability before every event and navigation
  (`BilimbiWeb.RouteAccess`). An operation that needs a different capability
  than the route re-asks here before writing or reading private facts.
  Component events first pass the same host identity and page check through
  the Base UI event wrapper; this helper checks the operation capability.

  One `Bilimbi.Base.Authz.can/2` decision per key, judged on the actor the
  authentication edge sealed; an `{:any_of, keys}` requirement stops at the
  first allow. The decision is logged like any other, so a refused event is
  visible in the decision log.

  ## In an event

      def handle_event("save", params, socket) do
        case LiveAuthorization.authorize_event(socket, "admin.company.update") do
          {:ok, socket} -> {:noreply, save(socket, params)}
          {:denied, socket} -> {:noreply, socket}
        end
      end

  The refused socket carries an error flash and no longer lists the denied
  keys in `current_scope.capabilities`, so a control hidden through
  `allowed?/2` disappears on the next render. A page that caches its own
  `can_*?` assign re-derives it from the returned socket.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Base.Menu.Capability
  alias Phoenix.LiveView.Socket

  @type requirement :: String.t() | {:any_of, [String.t()]}

  @denied_message "You do not have permission for that action."

  @doc "The flash shown when `authorize_event/2` refuses."
  @spec denied_message() :: String.t()
  def denied_message, do: @denied_message

  @doc """
  Whether the actor behind `current_scope` holds `requirement` right now.

  Takes the `current_scope` assign or its `Bilimbi.Base.Authz.Actor`. A scope
  with no sealed actor is refused: there is nobody to judge. `nil` is not a
  requirement; an operation always names what it needs.
  """
  @spec allowed_now?(map() | Actor.t() | nil, requirement()) :: boolean()
  def allowed_now?(%{actor: %Actor{} = actor}, requirement),
    do: allowed_now?(actor, requirement)

  def allowed_now?(%Actor{} = actor, requirement) do
    Capability.allowed?(requirement!(requirement), fn key ->
      match?(%Decision{allowed: true}, Authz.can(actor, key))
    end)
  end

  def allowed_now?(_no_actor, requirement) do
    _ = requirement!(requirement)
    false
  end

  @doc """
  Re-authorizes one operation inside an event handler.

  Returns `{:ok, socket}` when the actor holds `requirement` now, else
  `{:denied, socket}` with the refusal flashed and the denied keys dropped
  from `current_scope.capabilities`. The caller returns the denied socket
  from its handler unchanged; nothing else is needed to refuse.
  """
  @spec authorize_event(Socket.t(), requirement()) :: {:ok, Socket.t()} | {:denied, Socket.t()}
  def authorize_event(%Socket{} = socket, requirement) do
    requirement = requirement!(requirement)
    current_scope = socket.assigns[:current_scope]

    if allowed_now?(current_scope, requirement) do
      {:ok, socket}
    else
      {:denied,
       socket
       |> put_flash(:error, @denied_message)
       |> assign(:current_scope, withhold(current_scope, Capability.keys(requirement)))}
    end
  end

  defp withhold(%{capabilities: capabilities} = current_scope, keys)
       when is_list(capabilities) do
    %{current_scope | capabilities: capabilities -- keys}
  end

  defp withhold(current_scope, _keys), do: current_scope

  defp requirement!(requirement) when is_binary(requirement) do
    if String.trim(requirement) == "" do
      raise ArgumentError, "a capability requirement cannot be blank"
    end

    requirement
  end

  defp requirement!({:any_of, _} = requirement) do
    if Capability.valid?(requirement) do
      requirement
    else
      raise ArgumentError, "invalid any-of capability requirement: #{inspect(requirement)}"
    end
  end

  defp requirement!(requirement) do
    raise ArgumentError,
          "an operation names the capability it needs; got #{inspect(requirement)}"
  end
end
