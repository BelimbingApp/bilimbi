defmodule Bilimbi.Core.User.Web.FormLive do
  @moduledoc """
  Creates and edits user accounts through the Core User public API.

  The trusted authenticated admin form submits a plaintext `:password` only
  when creating an account. Core User validates and hashes it; the adapter
  never accepts a caller-supplied hash or hashes a credential itself.
  """

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias Ecto.Changeset

  @field_types %{
    name: :string,
    email: :string,
    password: :string,
    company_id: :integer
  }

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    {:ok, companies} = Company.list_companies(scope)

    {:ok,
     socket
     |> assign(:active_nav, "admin.user")
     |> assign(:companies, companies)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_route(socket, params)}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign_form(socket, form_changeset(params, socket.assigns.mode))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    save(socket, socket.assigns.mode, params)
  end

  defp apply_route(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope.scope

    with {user_id, ""} <- Integer.parse(id),
         {:ok, %User.Summary{company_id: company_id} = user} <-
           User.get_tenant_user(scope, user_id),
         true <- is_integer(company_id) do
      socket
      |> assign(:page_title, "Edit User")
      |> assign(:mode, :edit)
      |> assign(:user, user)
      |> assign_form(form_changeset(%{"name" => user.name, "email" => user.email}, :edit))
    else
      _ ->
        socket
        |> put_flash(:error, "That user does not exist in this workspace.")
        |> push_navigate(to: ~p"/users")
    end
  end

  defp apply_route(socket, _params) do
    socket
    |> assign(:page_title, "Create User")
    |> assign(:mode, :new)
    |> assign(:user, nil)
    |> assign_form(form_changeset(%{}, :new))
  end

  defp save(socket, :new, params) do
    changeset = form_changeset(params, :new)
    scope = socket.assigns.current_scope.scope

    if changeset.valid? do
      attributes = Map.take(params, ["name", "email", "password"])
      company_id = Changeset.get_field(changeset, :company_id)

      case User.create_user(scope, company_id, attributes) do
        {:ok, user} ->
          {:noreply,
           socket
           |> put_flash(:info, "User created successfully.")
           |> push_navigate(to: ~p"/users/#{user.id}")}

        {:error, :company_not_found} ->
          {:noreply,
           assign_form(socket, add_error(changeset, :company_id, "is not in this workspace"))}

        {:error, %Changeset{} = domain_changeset} ->
          {:noreply, assign_form(socket, copy_domain_errors(changeset, domain_changeset))}
      end
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params) do
    changeset = form_changeset(params, :edit)
    scope = socket.assigns.current_scope.scope
    user = socket.assigns.user

    if changeset.valid? do
      attributes = Map.take(params, ["name", "email"])

      case User.update_user(scope, user.company_id, user.id, attributes) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> put_flash(:info, "User updated successfully.")
           |> push_navigate(to: ~p"/users/#{updated.id}")}

        {:error, %Changeset{} = domain_changeset} ->
          {:noreply, assign_form(socket, copy_domain_errors(changeset, domain_changeset))}

        {:error, :company_not_found} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "That user cannot be edited while their company is archived."
           )}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "That user could not be updated.")}
      end
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp form_changeset(params, mode) do
    required =
      if mode == :new,
        do: [:company_id, :name, :email, :password],
        else: [:name, :email]

    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required(required)
    |> validate_length(:password, min: 8)
    |> Map.put(:action, :validate)
  end

  defp copy_domain_errors(form_changeset, %Changeset{} = domain_changeset) do
    domain_changeset.errors
    |> Enum.reduce(form_changeset, fn {field, {message, opts}}, acc ->
      if Map.has_key?(@field_types, field), do: add_error(acc, field, message, opts), else: acc
    end)
    |> Map.put(:action, :insert)
  end

  defp assign_form(socket, %Changeset{} = changeset),
    do: assign(socket, :form, to_form(changeset, as: :user))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-xl">
        <.header>
          {@page_title}
          <:subtitle>{if @mode == :new, do: "Add a new user to the system", else: "Update user information"}</:subtitle>
          <:actions>
            <.button id="user-back" navigate={~p"/users"}>
              Back to users
            </.button>
          </:actions>
        </.header>

        <.form for={@form} id="user-form" phx-change="validate" phx-submit="save" class="rounded-xl border border-line bg-surface px-6 py-5">
          <.input :if={@mode == :new} field={@form[:company_id]} id="user-company" type="select" label="Company" prompt="Choose a company" options={for company <- @companies, do: {Company.Summary.display_name(company), company.id}} />
          <.input field={@form[:name]} id="user-name" label="Name" autocomplete="name" placeholder="Enter user name" required />
          <.input field={@form[:email]} id="user-email" type="email" label="Email" autocomplete="email" placeholder="Enter email address" required />

          <%= if @mode == :new do %>
            <.input field={@form[:password]} id="user-password" type="password" label="Password" autocomplete="new-password" placeholder="Enter password" required />
          <% end %>

          <div class="mt-2 flex items-center gap-4">
            <.button id="user-save" variant="primary" type="submit" phx-disable-with="Saving…">{if @mode == :new, do: "Create User", else: "Update User"}</.button>
            <.link id="user-cancel" navigate={~p"/users"} class="text-sm font-medium text-ink-muted hover:text-ink">Cancel</.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
