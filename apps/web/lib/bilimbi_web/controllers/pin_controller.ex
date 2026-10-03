defmodule BilimbiWeb.PinController do
  @moduledoc """
  REST endpoints for toggling and reordering sidebar pins (`/api/pins/*`).
  """

  use BilimbiWeb, :controller

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.UI.RouteContract
  alias Bilimbi.Core.User

  def index(conn, _params) do
    case tenancy_scope(conn) do
      %Scope{} = scope ->
        case shell_pins(scope) do
          {:ok, pins} ->
            json(conn, %{pins: pins})

          {:error, reason} ->
            respond_to_actor_error(conn, reason)
        end

      nil ->
        respond_to_actor_error(conn, :unauthorized)
    end
  end

  @doc """
  The signed-in user's pins whose routes this deployment still serves.

  `BilimbiWeb.UserAuth` stores the list on the scope and the shell renders
  it. `GET /api/pins` remains for a refresh after a toggle when the rendered
  list is not what the hook should keep. An unauthorized scope stays an
  error so that endpoint does not answer `200` with an empty list.
  """
  def shell_pins(%Scope{} = scope) do
    case User.list_user_pins(scope) do
      {:ok, pins} ->
        {:ok, pins |> Enum.filter(&served_pin?/1) |> format_pins()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def toggle(conn, %{"label" => label, "url" => url} = params)
      when is_binary(label) and is_binary(url) do
    case tenancy_scope(conn) do
      %Scope{} = scope ->
        case User.toggle_user_pin(scope, params) do
          {:ok, action, pins} ->
            json(conn, %{
              pinned: action == :pinned,
              pins: format_pins(pins)
            })

          {:error, reason} when reason in [:unauthorized, :impersonating] ->
            respond_to_actor_error(conn, reason)

          {:error, _changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "invalid_pin"})
        end

      nil ->
        respond_to_actor_error(conn, :unauthorized)
    end
  end

  def toggle(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid_parameters"})
  end

  def reorder(conn, %{"pins" => pin_list}) when is_list(pin_list) do
    case tenancy_scope(conn) do
      %Scope{} = scope ->
        case pin_ids(pin_list) do
          {:ok, pin_ids} ->
            case User.reorder_user_pins(scope, pin_ids) do
              {:ok, pins} ->
                json(conn, %{pins: format_pins(pins)})

              {:error, reason} ->
                respond_to_actor_error(conn, reason)
            end

          :error ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "invalid_parameters"})
        end

      nil ->
        respond_to_actor_error(conn, :unauthorized)
    end
  end

  def reorder(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid_parameters"})
  end

  defp tenancy_scope(conn) do
    case conn.assigns[:current_scope] do
      %{scope: %Scope{} = scope} -> scope
      _ -> nil
    end
  end

  defp respond_to_actor_error(conn, :impersonating) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "impersonating"})
  end

  defp respond_to_actor_error(conn, :unauthorized) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized"})
  end

  # Keep stale durable pins out of the shell when a module route is removed.
  # The toggle and reorder compatibility endpoints intentionally retain their
  # existing response semantics; only the shell's read is route-aware.
  defp served_pin?(pin) do
    pin.url
    |> URI.parse()
    |> Map.get(:path)
    |> then(&RouteContract.verified_route?([], String.split(&1 || "/", "/", trim: true)))
  end

  # The client controls this list. `String.to_integer/1` raises on anything
  # non-numeric and the map clauses had no catch-all, so a malformed payload
  # became a 500 -- the crash #302 fixed on the Countries screen, in new code.
  #
  # The whole request is rejected rather than the bad entries dropped: a
  # partial reorder would renumber some pins and leave the sidebar disagreeing
  # with the server, which is harder to notice than an error.
  defp pin_ids(pin_list) do
    result =
      Enum.reduce_while(pin_list, {:ok, []}, fn entry, {:ok, acc} ->
        case pin_id(entry) do
          {:ok, id} -> {:cont, {:ok, [id | acc]}}
          :error -> {:halt, :error}
        end
      end)

    case result do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      :error -> :error
    end
  end

  defp pin_id(%{"id" => id}), do: pin_id(id)
  defp pin_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp pin_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp pin_id(_other), do: :error

  defp format_pins(pins) do
    Enum.map(pins, fn pin ->
      %{
        id: pin.id,
        label: pin.label,
        url: pin.url,
        icon: pin.icon,
        sort_order: pin.sort_order
      }
    end)
  end
end
