defmodule Bilimbi.Core.Employee.Web.TypeFormLive do
  @moduledoc """
  Create or edit a custom employee type for the signed-in company.

  System types cannot be edited; custom types belong to the company and
  their codes are immutable after creation.
  """

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Core.Employee
  alias Ecto.Changeset

  @field_types %{code: :string, label: :string}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :active_nav, "admin.employee-type")}
  end

  @impl true
  def handle_params(%{"id" => _} = params, _uri, socket) do
    {:noreply, apply_action(assign(socket, :live_action, :edit), :edit, params)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(assign(socket, :live_action, :new), :new, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Employee Type")
    |> assign(:type, nil)
    |> assign_form(form_changeset(:new, %{}, nil))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    with {type_id, ""} <- Integer.parse(id),
         {:ok, type} <- Employee.get_employee_type(scope, company_id, type_id) do
      if type.is_system do
        socket
        |> put_flash(:error, "System employee types cannot be edited.")
        |> push_navigate(to: ~p"/employee-types")
      else
        socket
        |> assign(:page_title, "Edit #{type.label}")
        |> assign(:type, type)
        |> assign_form(form_changeset(:edit, %{"label" => type.label}, type))
      end
    else
      {:error, :company_not_found} ->
        socket
        |> put_flash(:error, "That company is not in this workspace.")
        |> push_navigate(to: ~p"/dashboard")

      _ ->
        socket
        |> put_flash(:error, "That employee type does not exist in this company.")
        |> push_navigate(to: ~p"/employee-types")
    end
  end

  @impl true
  def handle_event("validate", %{"employee_type" => params}, socket) do
    action = socket.assigns.live_action
    type = socket.assigns.type
    {:noreply, assign_form(socket, form_changeset(action, params, type))}
  end

  def handle_event("save", %{"employee_type" => params}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]
    action = socket.assigns.live_action
    type = socket.assigns.type
    changeset = form_changeset(action, params, type)

    if changeset.valid? do
      case action do
        :new ->
          attributes = Map.take(params, ["code", "label"])

          case Employee.create_employee_type(scope, company_id, attributes) do
            {:ok, new_type} ->
              {:noreply,
               socket
               |> put_flash(:info, "#{new_type.label} was created.")
               |> push_navigate(to: ~p"/employee-types")}

            {:error, :company_not_found} ->
              {:noreply, put_flash(socket, :error, "That company is not in this workspace.")}

            {:error, %Changeset{} = domain_changeset} ->
              {:noreply,
               assign_form(socket, copy_domain_errors(changeset, domain_changeset, :insert))}
          end

        :edit ->
          attributes = %{"label" => get_change(changeset, :label) || type.label}

          case Employee.update_employee_type(scope, company_id, type.id, attributes) do
            {:ok, updated_type} ->
              {:noreply,
               socket
               |> put_flash(:info, "#{updated_type.label} was updated.")
               |> push_navigate(to: ~p"/employee-types")}

            {:error, :company_not_found} ->
              {:noreply, put_flash(socket, :error, "That company is not in this workspace.")}

            {:error, :is_system} ->
              {:noreply,
               socket
               |> put_flash(:error, "System employee types cannot be edited.")
               |> push_navigate(to: ~p"/employee-types")}

            {:error, :type_not_found} ->
              {:noreply,
               socket
               |> put_flash(:error, "That employee type does not exist in this company.")
               |> push_navigate(to: ~p"/employee-types")}

            {:error, %Changeset{} = domain_changeset} ->
              {:noreply,
               assign_form(socket, copy_domain_errors(changeset, domain_changeset, :update))}
          end
      end
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp form_changeset(:new, params, _type) do
    {%{}, @field_types}
    |> cast(params, [:code, :label])
    |> validate_required([:code, :label])
    |> Map.put(:action, :validate)
  end

  defp form_changeset(:edit, params, type) do
    initial_code = if type, do: type.code, else: nil

    {%{code: initial_code}, @field_types}
    |> cast(params, [:label])
    |> validate_required([:label])
    |> Map.put(:action, :validate)
  end

  defp copy_domain_errors(form_changeset, %Changeset{} = domain_changeset, action) do
    domain_changeset.errors
    |> Enum.reduce(form_changeset, fn {field, {message, opts}}, acc ->
      if Map.has_key?(@field_types, field) do
        add_error(acc, field, message, opts)
      else
        acc
      end
    end)
    |> Map.put(:action, action)
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :employee_type))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:form}>
        <p class="mb-2 text-xs">
          <.link navigate={~p"/employee-types"} class="font-medium text-ink-muted hover:text-ink">
            ← Employee Types
          </.link>
        </p>

        <.header>
          {@page_title}
          <:subtitle>
            <%= if @live_action == :new do %>
              Custom types belong to this company. System type codes are reserved.
            <% else %>
              Update the display label for this custom employee type. The code is permanent.
            <% end %>
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="employee-type-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-5 flex flex-col gap-4 rounded-xl border border-line bg-surface px-6 py-5"
        >
          <.input field={@form[:label]} id="employee-type-label" label="Label" autocomplete="off" />
          <.input
            field={@form[:code]}
            id="employee-type-code"
            label="Code"
            autocomplete="off"
            disabled={@live_action == :edit}
          />
          <div class="mt-2 flex items-center gap-3">
            <.button
              id="employee-type-save"
              variant="primary"
              type="submit"
              phx-disable-with="Saving…"
            >
              Save type
            </.button>

            <.link
              navigate={~p"/employee-types"}
              class="text-sm font-medium text-ink-muted hover:text-ink"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </.page>
    </Layouts.app>
    """
  end
end
