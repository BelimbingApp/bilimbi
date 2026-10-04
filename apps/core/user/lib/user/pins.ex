defmodule Bilimbi.Core.User.Pins do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User.Pin

  @doc "Lists all pinned items for the signed-in user, ordered by sort_order."
  @spec list_user_pins(Scope.t()) :: {:ok, [Pin.t()]} | {:error, :unauthorized}
  def list_user_pins(%Scope{} = scope) do
    with {:ok, user_id} <- reader(scope) do
      {:ok, pins_for(user_id)}
    end
  end

  defp pins_for(user_id) do
    from(p in Pin,
      where: p.user_id == ^user_id,
      order_by: [asc: p.sort_order, asc: p.id]
    )
    |> Repo.all()
  end

  @spec toggle_user_pin(Scope.t(), map()) ::
          {:ok, :pinned | :unpinned, [Pin.t()]}
          | {:error, Changeset.t() | :unauthorized | :impersonating}
  def toggle_user_pin(%Scope{} = scope, attrs) when is_map(attrs) do
    with {:ok, user_id} <- writer(scope) do
      toggle_pin(user_id, attrs)
    end
  end

  defp toggle_pin(user_id, attrs) do
    url = Map.get(attrs, "url") || Map.get(attrs, :url) || ""
    url_hash = Pin.hash_url(to_string(url))

    existing =
      from(p in Pin,
        where: p.user_id == ^user_id and p.url_hash == ^url_hash
      )
      |> Repo.one()

    case existing do
      %Pin{} = pin ->
        with {:ok, _deleted} <- Repo.delete(pin) do
          {:ok, :unpinned, pins_for(user_id)}
        end

      nil ->
        max_order =
          from(p in Pin,
            where: p.user_id == ^user_id,
            select: max(p.sort_order)
          )
          |> Repo.one() || -1

        attrs_with_defaults =
          attrs
          |> Map.put("user_id", user_id)
          |> Map.put_new("sort_order", max_order + 1)

        %Pin{}
        |> Pin.changeset(attrs_with_defaults)
        |> Repo.insert()
        |> case do
          {:ok, _pin} -> {:ok, :pinned, pins_for(user_id)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @spec reorder_user_pins(Scope.t(), [pos_integer()]) ::
          {:ok, [Pin.t()]} | {:error, :unauthorized | :impersonating}
  def reorder_user_pins(%Scope{} = scope, ordered_pin_ids) when is_list(ordered_pin_ids) do
    with {:ok, user_id} <- writer(scope) do
      reorder_pins(user_id, ordered_pin_ids)
    end
  end

  defp reorder_pins(user_id, ordered_pin_ids) do
    # The order pins appear in is a display preference of the signed-in
    # user's own, not a business fact; pinning and unpinning are ordinary
    # writes and stay captured.
    Audit.without_auditing(fn ->
      Repo.transaction(fn ->
        Enum.each(Enum.with_index(ordered_pin_ids), fn {pin_id, index} ->
          from(p in Pin,
            where: p.user_id == ^user_id and p.id == ^pin_id
          )
          |> Repo.update_all(set: [sort_order: index])
        end)

        pins_for(user_id)
      end)
    end)
  end

  # A read follows the account being viewed, including under impersonation.
  defp reader(%Scope{} = scope) do
    case Scope.actor(scope) do
      %TenancyActor{type: :user, user_id: user_id} when is_integer(user_id) and user_id > 0 ->
        {:ok, user_id}

      %TenancyActor{} ->
        {:error, :unauthorized}
    end
  end

  # Changing pins while impersonating is refused here, once, rather than in
  # each controller that used to re-check `scope.impersonator`.
  defp writer(%Scope{} = scope) do
    case Scope.actor(scope) do
      %TenancyActor{type: :user, impersonator_id: impersonator_id}
      when not is_nil(impersonator_id) ->
        {:error, :impersonating}

      %TenancyActor{type: :user, user_id: user_id} when is_integer(user_id) and user_id > 0 ->
        {:ok, user_id}

      %TenancyActor{} ->
        {:error, :unauthorized}
    end
  end
end
