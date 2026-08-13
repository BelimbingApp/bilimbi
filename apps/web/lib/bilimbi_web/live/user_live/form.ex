defmodule BilimbiWeb.UserLive.Form do
  @moduledoc """
  User create/edit form — the reference implementation for Bilimbi forms.

  Conventions this screen establishes:

    * The form is a schemaless `Ecto.Changeset` owned by the LiveView and
      assigned with `to_form/2`; templates read `@form[:field]`.
    * The domain API (`Bilimbi.Core.User`) stays the only writer. On a
      domain changeset error, its messages are copied onto the form
      changeset so the user sees field-level feedback without Web
      duplicating business rules.
    * Company affiliation is chosen from the live tenant company list and
      proven again inside `Core.User`; the form never trusts the id.
    * Edit does not move a user between companies and never touches the
      credential: password changes stay in the account's own flows.
  """

  use BilimbiWeb, :live_view

  import Ecto.Changeset

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias Ecto.Changeset

  @field_types %{name: :string, email: :string, password: :string, company_id: :integer}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    {:ok, companies} = Company.list_companies(scope)

    {:ok,
     socket
     |> assign(:active_nav, :users)
     |> assign(:companies, companies)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New user")
    |> assign(:user, nil)
    |> assign_form(form_changeset(%{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope.scope

    with {user_id, ""} <- Integer.parse(id),
         {:ok, users} <- User.list_users(scope),
         %User.Summary{company_id: company_id} when is_integer(company_id) <-
           Enum.find(users, &(&1.id == user_id)),
         {:ok, user} <- User.get_user(scope, company_id, user_id) do
      socket
      |> assign(:page_title, "Edit #{user.name}")
      |> assign(:user, user)
      |> assign_form(form_changeset(%{"name" => user.name, "email" => user.email}))
    else
      _ ->
        socket
        |> put_flash(:error, "That user does not exist in this workspace.")
        |> push_navigate(to: ~p"/users")
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign_form(socket, form_changeset(params, socket.assigns.live_action))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    scope = socket.assigns.current_scope.scope
    changeset = form_changeset(params, :new)

    if changeset.valid? do
      attributes = Map.take(params, ["name", "email", "password"])
      company_id = Changeset.get_field(changeset, :company_id)

      case User.register_user(scope, company_id, attributes) do
        {:ok, user} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{user.name} can now sign in once their email is verified.")
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
    scope = socket.assigns.current_scope.scope
    user = socket.assigns.user
    changeset = form_changeset(params, :edit)

    if changeset.valid? do
      attributes = Map.take(params, ["name", "email"])

      case User.update_user(scope, user.company_id, user.id, attributes) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{updated.name} was updated.")
           |> push_navigate(to: ~p"/users/#{updated.id}")}

        {:error, %Changeset{} = domain_changeset} ->
          {:noreply, assign_form(socket, copy_domain_errors(changeset, domain_changeset))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "That user could not be updated.")}
      end
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp form_changeset(params, action \\ :new) do
    required =
      case action do
        :new -> [:name, :email, :password, :company_id]
        :edit -> [:name, :email]
      end

    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required(required)
    |> validate_length(:name, max: 255)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:password, min: 8)
    |> Map.put(:action, :validate)
  end

  defp copy_domain_errors(form_changeset, %Changeset{} = domain_changeset) do
    domain_changeset.errors
    |> Enum.reduce(form_changeset, fn {field, {message, opts}}, acc ->
      if Map.has_key?(@field_types, field) do
        add_error(acc, field, message, opts)
      else
        acc
      end
    end)
    |> Map.put(:action, :insert)
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :user))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-xl">
        <p class="mb-2 text-xs">
          <.link navigate={~p"/users"} class="font-medium text-ink-muted hover:text-ink">
            ← Users
          </.link>
        </p>

        <.header>
          {@page_title}
          <:subtitle>
            <%= if @live_action == :new do %>
              Creates an unverified account in the chosen company.
            <% else %>
              Changing the email marks the account unverified until it is confirmed again.
            <% end %>
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="user-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-5 flex flex-col gap-4 rounded-xl border border-line bg-surface px-6 py-5"
        >
          <.input field={@form[:name]} id="user-name" label="Name" autocomplete="off" />
          <.input
            field={@form[:email]}
            id="user-email"
            type="email"
            label="Email"
            autocomplete="off"
          />
          <.input
            :if={@live_action == :new}
            field={@form[:password]}
            id="user-password"
            type="password"
            label="Temporary password"
            autocomplete="new-password"
          />
          <.input
            :if={@live_action == :new}
            field={@form[:company_id]}
            id="user-company"
            type="select"
            label="Company"
            prompt="Choose a company"
            options={
              for company <- @companies, do: {Company.Summary.display_name(company), company.id}
            }
          />

          <div class="mt-2 flex items-center gap-3">
            <.button id="user-save" variant="primary" type="submit" phx-disable-with="Saving…">
              Save user
            </.button>
            <.link
              navigate={~p"/users"}
              class="text-sm font-medium text-ink-muted hover:text-ink"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
