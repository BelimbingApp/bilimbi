defmodule Bilimbi.Core.User.Web.PasswordLive do
  @moduledoc """
  The signed-in account's self-service password update screen.

  Ports Belimbing's `app/Core/User/Livewire/Settings/Password.php`.
  Requires verification of the user's current password before updating to a
  new Argon2id password hash.
  """

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset
  import Bilimbi.Core.User.Web.SettingsComponents

  alias Bilimbi.Core.User
  alias Ecto.Changeset

  @field_types %{
    current_password: :string,
    password: :string,
    password_confirmation: :string
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_empty_form(socket)}
  end

  @impl true
  def handle_event("validate", %{"password_change" => params}, socket) do
    changeset =
      params
      |> change_password_changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :password_change))}
  end

  @impl true
  def handle_event("save", %{"password_change" => params}, socket) do
    changeset = change_password_changeset(params)

    if changeset.valid? do
      current_password = get_change(changeset, :current_password)
      new_password = get_change(changeset, :password)

      current_scope = socket.assigns.current_scope
      user_id = extract_user_id(current_scope)
      company_id = extract_company_id(current_scope)
      scope = current_scope.scope

      case User.change_password(scope, company_id, user_id, current_password, new_password) do
        {:ok, _user} ->
          socket =
            socket
            |> put_flash(:info, "Password updated successfully.")
            |> assign_empty_form()

          {:noreply, socket}

        {:error, :invalid_password} ->
          changeset =
            changeset
            |> add_error(:current_password, "is incorrect")
            |> Map.put(:action, :validate)

          {:noreply, assign(socket, form: to_form(changeset, as: :password_change))}

        {:error, %Changeset{} = domain_changeset} ->
          changeset =
            changeset
            |> merge_domain_errors(domain_changeset)
            |> Map.put(:action, :validate)

          {:noreply, assign(socket, form: to_form(changeset, as: :password_change))}

        {:error, _other} ->
          {:noreply, put_flash(socket, :error, "Could not update password.")}
      end
    else
      {:noreply,
       assign(socket,
         form: to_form(Map.put(changeset, :action, :validate), as: :password_change)
       )}
    end
  end

  defp assign_empty_form(socket) do
    changeset = change_password_changeset(%{})
    assign(socket, form: to_form(changeset, as: :password_change))
  end

  defp change_password_changeset(attrs) do
    {%{}, @field_types}
    |> cast(attrs, [:current_password, :password, :password_confirmation])
    |> validate_required([:current_password, :password, :password_confirmation])
    |> validate_length(:password, min: 8)
    |> validate_confirmation(:password, message: "does not match password")
  end

  defp merge_domain_errors(target_changeset, %Changeset{errors: errors}) do
    Enum.reduce(errors, target_changeset, fn {field, {msg, opts}}, acc ->
      add_error(acc, field, msg, opts)
    end)
  end

  defp extract_user_id(%{user: %{"user_id" => id}}), do: id
  defp extract_user_id(%{user: %{user_id: id}}), do: id
  defp extract_user_id(%{user: %{id: id}}), do: id
  defp extract_user_id(%{actor: %{id: id}}), do: id

  defp extract_company_id(%{user: %{"company_id" => id}}), do: id
  defp extract_company_id(%{user: %{company_id: id}}), do: id
  defp extract_company_id(%{actor: %{company_id: id}}), do: id
end
