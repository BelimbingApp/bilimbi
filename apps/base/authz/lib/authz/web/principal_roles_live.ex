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

  @sortable ~w(created_at principal_type principal_id principal_name role_name company_id company_name)

  @impl true
  def mount(_params, _session, socket) do
    companies = Authz.companies_in_scope(socket.assigns.current_scope.scope)

    {:ok,
     socket
     |> assign(:page_title, "Principal Roles")
     |> assign(:company_names, Map.new(companies, &{&1.id, &1.name}))
     |> assign(:company_order, Enum.map(companies, & &1.id))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    state = %{socket.assigns.state | search: Map.get(params, "search", ""), page: 1}
    {:noreply, push_state(socket, state)}
  end

  @impl true
  def handle_event("sort", %{"sort" => column}, socket) when column in @sortable do
    state = socket.assigns.state
    column = String.to_existing_atom(column)

    direction =
      cond do
        state.sort_by != column -> default_direction(column)
        state.sort_dir == :asc -> :desc
        true -> :asc
      end

    {:noreply, push_state(socket, %{state | sort_by: column, sort_dir: direction, page: 1})}
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, %{socket.assigns.state | page: to_int(page, 1)})}
  end

  defp default_direction(:created_at), do: :desc
  defp default_direction(_column), do: :asc

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/authz/principal-roles?#{state_to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Authz.list_principal_roles(socket.assigns.current_scope.scope,
        search: nilify(state.search),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: 25,
        company_order: socket.assigns.company_order
      )

    if beyond_last_page?(page) do
      load(socket, %{state | page: page.total_pages})
    else
      socket
      |> assign(:state, state)
      |> assign(:page, page)
      |> stream(:assignments, page.entries, reset: true)
    end
  end

  defp beyond_last_page?(page),
    do: page.total_pages > 0 and page.page > page.total_pages

  defp state_from_params(params) do
    %{
      search: Map.get(params, "search", ""),
      sort_by: sort_by_from(Map.get(params, "sort_by")),
      sort_dir: sort_dir_from(params),
      page: to_int(Map.get(params, "page"), 1)
    }
  end

  defp state_to_params(state) do
    %{
      "search" => state.search,
      "sort_by" => state.sort_by,
      "sort_dir" => state.sort_dir,
      "page" => state.page
    }
  end

  defp sort_by_from(value) when value in @sortable, do: String.to_existing_atom(value)
  defp sort_by_from(_value), do: :created_at

  defp sort_dir_from(%{"sort_dir" => "asc"}), do: :asc
  defp sort_dir_from(%{"sort_dir" => "desc"}), do: :desc

  defp sort_dir_from(params),
    do: params |> Map.get("sort_by") |> sort_by_from() |> default_direction()

  defp to_int(nil, default), do: default

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp to_int(value, _default) when is_integer(value) and value > 0, do: value
  defp to_int(_value, default), do: default

  defp nilify(""), do: nil
  defp nilify(value), do: value

  defp principal_label(%{principal_type: "agent"}), do: "Employee"
  defp principal_label(%{principal_type: "user"}), do: "User"
  defp principal_label(%{principal_type: other}), do: to_string(other)

  # The Type column already says which kind this is, so the Principal column
  # carries the name when the directory resolved one and the durable id when it
  # did not. An unresolved principal is not an error and must not read as one.
  defp principal_identity(%{principal_name: name}) when is_binary(name) and name != "", do: name
  defp principal_identity(%{principal_id: id}), do: to_string(id)

  defp created_at(%{created_at: nil}), do: "—"
  defp created_at(%{created_at: at}), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")

  defp assignment_noun(1), do: "assignment"
  defp assignment_noun(_count), do: "assignments"

  defp company_name(_names, nil), do: "Global"

  defp company_name(names, company_id) do
    case Map.fetch(names, company_id) do
      {:ok, name} -> name
      :error -> to_string(company_id)
    end
  end
end
