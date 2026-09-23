defmodule Bilimbi.Core.Employee.Web.TypeShowLive do
  @moduledoc """
  Read-first LiveView adapter for one employee type visible to the signed-in
  company.

  An employee type has no detail page in Belimbing: its record's page is
  `admin/employee-types/{id}/edit`, a form holding the immutable code as text
  and the label as the one input. A record's page is read-first whether or
  not it is called a detail page, so this page shows the type as facts and an
  operator holding `admin.employee-type.update` edits the label in place, as
  on `/addresses/:id`, `/users/:id`, `/employees/:id` and `/companies/:id`.
  There is no edit mode, no save button and no separate edit form:

  - the label commits on Enter or on leaving the field through
    `<.inline_edit>`; Escape cancels. The column is required, so an emptied
    input commits nothing at the hook and a forged blank is refused by the
    domain;
  - the code is permanent after creation and reads as text, as Belimbing's
    page says under it;
  - a system type belongs to no company and cannot be edited by anyone, so
    its facts read as text for every actor, with the reason beside them.

  The label reports its own outcome through the shared commit status that
  `Bilimbi.Base.UI.CommitStatus` keeps: "Saving…" while the round trip is in
  flight, "Saved" once stored, and an alert on the fact naming the rejected
  value and the validation error when the save was refused. The stored value
  stays on screen until the server confirms a change, and success does not
  flash. Employee types are not audited in Belimbing or Bilimbi, so the
  header carries no history action: only the demoted "← Back" link.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.CommitStatus
  alias Bilimbi.Core.Employee

  @update_capability "admin.employee-type.update"

  # The facts an inline text edit may write, keyed by the form name the hook
  # pushes. A name outside this map is ignored; user input never becomes an atom.
  @inline_fields %{"label" => :label}

  @fact_labels %{"code" => "Code", "label" => "Label", "kind" => "Kind"}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    with {:ok, type_id} <- parse_id(id),
         {:ok, type} <- Employee.get_employee_type(scope, company_id, type_id) do
      {:ok,
       socket
       |> assign(:active_nav, "admin.employee-type")
       |> assign(:type_id, type_id)
       |> assign(:can_update?, allowed?(socket.assigns.current_scope, @update_capability))
       |> CommitStatus.init()
       |> assign_type(type)}
    else
      {:error, :company_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That company is not in this workspace.")
         |> push_navigate(to: ~p"/dashboard")}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "That employee type does not exist in this company.")
         |> push_navigate(to: ~p"/employee-types")}
    end
  end

  @impl true
  def handle_event("save_field", params, socket) do
    if can_update?(socket) do
      case CommitStatus.inline_field(params, @inline_fields) do
        {:ok, name, field, value} -> {:noreply, save_fact(socket, name, field, value)}
        :error -> {:noreply, socket}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  # One commit, one outcome on the fact that made it. The domain trims the
  # label and refuses a blank, an overlong value and a system type; each
  # refusal lands on the fact with the stored value still on screen.
  defp save_fact(socket, name, field, submitted) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    case Employee.update_employee_type(scope, company_id, socket.assigns.type_id, %{
           field => submitted
         }) do
      {:ok, type} ->
        socket
        |> assign_type(type)
        |> CommitStatus.put(name, :saved)

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          CommitStatus.refusal_message(fact_label(name), field, submitted, changeset.errors)

        CommitStatus.put(socket, name, {:error, message})

      {:error, reason} ->
        CommitStatus.put(socket, name, {:error, failure_message(reason)})
    end
  end

  defp assign_type(socket, type) do
    socket
    |> assign(:type, type)
    |> assign(:page_title, type.label)
  end

  defp failure_message(:is_system), do: "System employee types cannot be edited."

  defp failure_message(:type_not_found),
    do: "This employee type no longer exists. Return to the list to find its replacement."

  defp failure_message(_reason), do: CommitStatus.failure_message()

  defp write_forbidden(socket) do
    CommitStatus.write_forbidden(socket, "You do not have permission to update employee types.")
  end

  # Every write re-asks Authz: the `can_update?` assign decides what the page
  # shows, and a grant revoked while the page is open must still be refused.
  defp can_update?(socket) do
    Authz.can(socket.assigns.current_scope.actor, @update_capability).allowed
  end

  defp fact_label(name), do: Map.fetch!(@fact_labels, name)

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_id(_id), do: :error

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="employee-type-show-page" variant={:detail}>
        <.header>
          {@type.label}
          <:subtitle><code class="text-xs font-medium">{@type.code}</code></:subtitle>
          <:actions>
            <div class="flex items-center gap-3">
              <.back_link
                id="employee-type-back"
                navigate={~p"/employee-types"}
                title="Back to employee types"
              />
            </div>
          </:actions>
        </.header>

        <div class="space-y-6">
          <.card
            id="employee-type-details-card"
            inner_class="p-5 sm:p-6"
            role="region"
            aria-labelledby="employee-type-details-heading"
          >
            <.section_heading id="employee-type-details-heading" title="Employee Type">
              <:description>
                <%= if @type.is_system do %>
                  System types are shared by every company and cannot be edited.
                <% else %>
                  Custom types belong to this company. The code is permanent; the label can change.
                <% end %>
              </:description>
            </.section_heading>

            <.list id="employee-type-facts">
              <:item title={fact_label("code")} id="employee-type-view-code">
                <code class="text-xs font-medium">{@type.code}</code>
              </:item>
              <:item title={fact_label("label")} id="employee-type-view-label">
                <.inline_edit
                  :if={@can_update? and not @type.is_system}
                  id="employee-type-label"
                  name="label"
                  label={fact_label("label")}
                  value={@type.label}
                  id_value={@type.id}
                  save_event="save_field"
                  status={@field_status["label"]}
                  class="font-medium"
                />
                <%!-- No editor, so the fact still needs a voice for a commit
                     the domain refuses: a system type's label is stored on
                     no company and a forged write lands its refusal here. --%>
                <div :if={not @can_update? or @type.is_system}>
                  <span class="font-medium">{@type.label}</span>
                  <.commit_status id="employee-type-label-status" status={@field_status["label"]} />
                </div>
              </:item>
              <:item title={fact_label("kind")} id="employee-type-view-kind">
                <.badge kind={if @type.is_system, do: :neutral, else: :success}>
                  {if @type.is_system, do: "system", else: "custom"}
                </.badge>
              </:item>
            </.list>
          </.card>
        </div>
      </.page>
    </Layouts.app>
    """
  end
end
