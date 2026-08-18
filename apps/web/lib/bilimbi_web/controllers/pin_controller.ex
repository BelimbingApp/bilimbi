defmodule BilimbiWeb.PinController do
  @moduledoc """
  REST endpoints for toggling and reordering sidebar pins (`/api/pins/*`).
  """

  use BilimbiWeb, :controller

  alias Bilimbi.Core.User

  def toggle(conn, %{"label" => label, "url" => url} = params)
      when is_binary(label) and is_binary(url) do
    scope = conn.assigns[:current_scope]

    if scope && scope[:user] do
      user_id = extract_user_id(scope)

      case User.toggle_user_pin(user_id, params) do
        {:ok, action, pins} ->
          json(conn, %{
            pinned: action == :pinned,
            pins: format_pins(pins)
          })

        {:error, _changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid_pin"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "unauthorized"})
    end
  end

  def toggle(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid_parameters"})
  end

  def reorder(conn, %{"pins" => pin_list}) when is_list(pin_list) do
    scope = conn.assigns[:current_scope]

    if scope && scope[:user] do
      user_id = extract_user_id(scope)

      case pin_ids(pin_list) do
        {:ok, pin_ids} ->
          {:ok, pins} = User.reorder_user_pins(user_id, pin_ids)
          json(conn, %{pins: format_pins(pins)})

        :error ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid_parameters"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "unauthorized"})
    end
  end

  def reorder(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid_parameters"})
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

  defp extract_user_id(%{user: %{"user_id" => id}}), do: id
  defp extract_user_id(%{user: %{user_id: id}}), do: id
  defp extract_user_id(%{user: %{id: id}}), do: id
  defp extract_user_id(%{actor: %{id: id}}), do: id
end
