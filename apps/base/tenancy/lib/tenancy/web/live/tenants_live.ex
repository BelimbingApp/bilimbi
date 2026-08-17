defmodule Bilimbi.Base.Tenancy.Web.TenantsLive do
  @moduledoc """
  Platform tenant list and create form.

  Parent names and child counts are derived from `Tenancy.list_tenants/0`
  rather than leaking association preloads across the module boundary.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Tenancy
  alias Ecto.Changeset

  @sortable ~w(id name status)
  @create_cap "admin.tenancy.tenant.create"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tenants")
     |> assign(:sort_by, "id")
     |> assign(:sort_dir, :asc)
     |> assign(:show_create, false)
     |> assign_form(create_changeset(%{}))
     |> refresh_tenants()}
  end

  @impl true
  def handle_event("sort", %{"sort" => column}, socket) when column in @sortable do
    {sort_by, sort_dir} = toggle_sort(socket.assigns.sort_by, socket.assigns.sort_dir, column)

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:sort_dir, sort_dir)
     |> refresh_tenants()}
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  def handle_event("show_create", _params, socket) do
    if can_create?(socket) do
      {:noreply,
       socket
       |> assign(:show_create, true)
       |> assign_form(create_changeset(%{}))}
    else
      {:noreply, refuse_create(socket)}
    end
  end

  def handle_event("cancel_create", _params, socket) do
    {:noreply, assign(socket, :show_create, false)}
  end

  def handle_event("create", params, socket) do
    if can_create?(socket) do
      changeset = create_changeset(Map.get(params, "tenant", %{}))

      case Changeset.apply_action(changeset, :insert) do
        {:ok, attrs} ->
          persist_tenant(socket, changeset, attrs)

        {:error, changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    else
      {:noreply, refuse_create(socket)}
    end
  end

  defp persist_tenant(socket, form_changeset, attrs) do
    case Tenancy.create_tenant(attrs) do
      {:ok, _tenant} ->
        {:noreply,
         socket
         |> assign(:show_create, false)
         |> assign_form(create_changeset(%{}))
         |> put_flash(:info, "Tenant created.")
         |> refresh_tenants()}

      {:error, %Changeset{} = domain_changeset} ->
        {:noreply, assign_form(socket, copy_errors(form_changeset, domain_changeset))}
    end
  end

  defp refuse_create(socket) do
    put_flash(socket, :error, "You do not have permission to create a tenant.")
  end

  defp can_create?(socket) do
    @create_cap in socket.assigns.current_scope.capabilities
  end

  defp refresh_tenants(socket) do
    identities = Tenancy.list_tenants()
    rows = present_tenants(identities, socket.assigns.sort_by, socket.assigns.sort_dir)

    socket
    |> assign(:tenants_count, length(rows))
    |> assign(:parent_options, parent_options(identities))
    |> stream(:tenants, rows, reset: true)
  end

  defp present_tenants(identities, sort_by, sort_dir) do
    names = Map.new(identities, &{&1.id, &1.name})
    child_counts = identities |> Enum.frequencies_by(& &1.parent_id) |> Map.delete(nil)

    identities
    |> Enum.map(fn identity ->
      %{
        id: identity.id,
        name: identity.name,
        is_platform_operator: identity.is_platform_operator,
        parent_name: names[identity.parent_id],
        children_count: Map.get(child_counts, identity.id, 0),
        status: identity.status
      }
    end)
    |> Enum.sort_by(&sort_value(&1, sort_by), sort_dir)
  end

  defp sort_value(row, "id"), do: row.id
  defp sort_value(row, "name"), do: row.name
  defp sort_value(row, "status"), do: row.status

  defp parent_options(identities) do
    identities
    |> Enum.sort_by(& &1.id)
    |> Enum.map(&{&1.name, &1.id})
  end

  defp toggle_sort(current_by, current_dir, column) do
    if current_by == column do
      {column, if(current_dir == :asc, do: :desc, else: :asc)}
    else
      {column, :asc}
    end
  end

  defp create_changeset(attrs) do
    types = %{name: :string, parent_id: :id, status: :string}

    {%{name: nil, parent_id: nil, status: "active"}, types}
    |> Changeset.cast(attrs, [:name, :parent_id, :status])
    |> Changeset.update_change(:name, &trim_name/1)
    |> Changeset.validate_required([:name, :status])
    |> Changeset.validate_length(:name, max: 255)
    |> Changeset.validate_inclusion(:status, ["active", "suspended"])
  end

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :tenant))
  end

  defp copy_errors(form_changeset, domain_changeset) do
    domain_changeset.errors
    |> Enum.reduce(form_changeset, fn {field, {message, opts}}, acc ->
      Changeset.add_error(acc, field, message, opts)
    end)
    |> Map.put(:action, :insert)
  end

  defp status_kind("active"), do: :success
  defp status_kind(_status), do: :neutral

  defp status_label("active"), do: "Active"
  defp status_label(status) when is_binary(status), do: String.capitalize(status)
end
