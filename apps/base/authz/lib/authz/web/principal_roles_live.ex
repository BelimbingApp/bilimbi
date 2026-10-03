defmodule Bilimbi.Base.Authz.Web.PrincipalRolesLive do
  @moduledoc """
  Role assignments across principals in the current tenant.

  Ports Belimbing's `app/Base/Authz/Livewire/PrincipalRoles/Index.php`.
  Belimbing joins `users` for name, email, search, and `principal_name` sort,
  and `companies` for the company column. Bilimbi reaches both through seams,
  because Base may not query Core. Company names use the `CompanyDirectory`
  seam (#183 / #382) and principal names the `PrincipalDirectory` seam (#441,
  ADR 0011), each with an id order resolved before pagination so display order
  survives a page boundary.

  Naming follows the hybrid #285 settled on: a principal inside the actor's
  tenant is named, one outside keeps its durable id. Belimbing's join is
  unscoped and names any user id it finds; that is not ported.

  Search covers role name and code, principal type, principal id, principal
  name, and provider-owned identity attributes such as a Core User email.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Params

  # Newest first, matching Belimbing: an assignment is usually being read
  # because somebody just granted or revoked one. The URL key is `per_page`.
  @list ListState.spec!(
          sortable: %{
            created_at: :desc,
            principal_type: :asc,
            principal_id: :asc,
            principal_name: :asc,
            role_name: :asc,
            company_id: :asc,
            company_name: :asc
          },
          default_sort: :created_at,
          page_sizes: [25, 50, 100, 300],
          default_page_size: 25,
          page_size_param: "per_page"
        )

  @impl true
  def mount(_params, _session, socket) do
    companies = Authz.companies_in_scope(socket.assigns.current_scope.scope)

    {:ok,
     socket
     |> assign(:page_title, "Principal Roles")
     |> assign(:reach_caution?, reach_caution?(socket))
     |> assign(:company_names, Map.new(companies, &{&1.id, &1.name}))
     |> assign(:company_order, Enum.map(companies, & &1.id))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, ListState.parse(params, @list))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_state(socket, ListState.apply_filters(socket.assigns.state, filters(params)))}
  end

  @impl true
  def handle_event("sort", %{"sort" => column}, socket) do
    state = socket.assigns.state

    case ListState.next_sort(state, column) do
      ^state -> {:noreply, socket}
      next -> {:noreply, push_state(socket, next)}
    end
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, ListState.put_page(socket.assigns.state, page))}
  end

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/authz/principal-roles?#{ListState.to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Authz.list_principal_roles(socket.assigns.current_scope.scope,
        search: Params.blank_to_nil(state.search),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: state.page_size,
        company_order: socket.assigns.company_order
      )

    corrected = ListState.clamp_to_last_page(state, page)

    if corrected.page != state.page do
      load(socket, corrected)
    else
      socket
      |> assign(:state, state)
      |> assign(:page, page)
      |> assign(:filters_form, ListState.filters_form(state))
      |> stream(:assignments, page.entries, reset: true)
    end
  end

  defp filters(params) when is_map(params), do: Map.get(params, "filters", %{})
  defp filters(_params), do: %{}

  defp principal_label(%{principal_type: "agent"}), do: "Employee"
  defp principal_label(%{principal_type: "user"}), do: "User"
  defp principal_label(%{principal_type: other}), do: to_string(other)

  # The Type column already says which kind this is, so the Principal column
  # carries the name when the directory resolved one and the durable id when it
  # did not. An unresolved principal is not an error and must not read as one.
  defp principal_identity(%{principal_name: name}) when is_binary(name) and name != "", do: name
  defp principal_identity(%{principal_id: id}), do: to_string(id)

  defp company_name(_names, nil), do: "Global"

  defp company_name(names, company_id) do
    case Map.fetch(names, company_id) do
      {:ok, name} -> name
      :error -> to_string(company_id)
    end
  end

  # `Authz` widens this listing for the platform-operator scope to rows attached
  # to no company (`Administration.company_visibility/2`). The caution names that
  # widening where the list is read; it changes nothing about what is listed.
  defp reach_caution?(socket) do
    Scope.platform_operator?(socket.assigns.current_scope.scope)
  end
end
