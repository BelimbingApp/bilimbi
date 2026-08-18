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

      pin_ids =
        Enum.map(pin_list, fn
          %{"id" => id} when is_integer(id) -> id
          %{"id" => id} when is_binary(id) -> String.to_integer(id)
          id when is_integer(id) -> id
          id when is_binary(id) -> String.to_integer(id)
        end)

      case User.reorder_user_pins(user_id, pin_ids) do
        {:ok, pins} ->
          json(conn, %{pins: format_pins(pins)})

        {:error, _reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "could_not_reorder"})
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
