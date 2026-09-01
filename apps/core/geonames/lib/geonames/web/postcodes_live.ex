defmodule Bilimbi.Core.Geonames.Web.PostcodesLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Core.Geonames

  import Bilimbi.Core.Geonames.Web.Components

  @page_sizes [25, 50, 100, 300]
  @sorts ~w(country_name postcode place_name admin1_code updated_at)
  @summary_sorts ~w(country_name country_iso record_count)
  @initial_directions %{"updated_at" => "desc"}
  @summary_initial_directions %{"record_count" => "desc"}
  @update_capability "admin.geonames.update"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:can_update?, allowed?(socket.assigns.current_scope, @update_capability))
     |> assign(:modal_action, nil)
     |> assign(:editing_postcode_id, nil)
     |> assign(:editing_revision, nil)
     |> assign(:postcode_form, nil)
     |> assign(:admin1_options, [])
     |> stream_configure(:postcodes, dom_id: &"postcode-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    state =
      socket.assigns.index_state
      |> Map.put(:search, Map.get(filters, "search", socket.assigns.index_state.search))
      |> Map.put(:per_page, Map.get(filters, "perPage", socket.assigns.index_state.per_page))
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: postcodes_path(state))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    {:noreply,
     push_patch(socket, to: postcodes_path(next_sort(socket.assigns.index_state, sort_by)))}
  end

  def handle_event("sort-summary", %{"sort" => sort_by}, socket) do
    state = next_summary_sort(socket.assigns.index_state, sort_by)
    {:noreply, push_patch(socket, to: postcodes_path(state))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    state =
      Map.put(
        socket.assigns.index_state,
        :page,
        bounded_page(page, socket.assigns.postcodes_page)
      )

    {:noreply, push_patch(socket, to: postcodes_path(state))}
  end

  def handle_event("new-postcode", _params, socket) do
    default_country = socket.assigns.countries |> List.first() |> then(&(&1 && &1.iso))
    attrs = %{country_iso: default_country, accuracy: 4}

    {:noreply,
     socket
     |> assign(:modal_action, :new)
     |> assign(:editing_postcode_id, nil)
     |> assign(:editing_revision, nil)
     |> assign(:admin1_options, admin1_options(default_country))
     |> assign_postcode_form(Geonames.change_postcode(attrs))}
  end

  def handle_event("edit-postcode", %{"id" => id}, socket) do
    case positive_id(id) do
      {:ok, id} ->
        case Map.get(socket.assigns.postcode_rows, id) do
          nil ->
            {:noreply, put_flash(socket, :error, "Postcode is no longer available.")}

          postcode ->
            attrs = postcode_attrs(postcode)

            {:noreply,
             socket
             |> assign(:modal_action, :edit)
             |> assign(:editing_postcode_id, postcode.id)
             |> assign(:editing_revision, postcode.revision)
             |> assign(:admin1_options, admin1_options(postcode.country_iso))
             |> assign_postcode_form(Geonames.change_postcode(attrs))}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Postcode is no longer available.")}
    end
  end

  def handle_event("close-postcode-modal", _params, socket) do
    {:noreply, close_postcode_modal(socket)}
  end

  def handle_event("validate-postcode", %{"postcode" => params}, socket) do
    country_iso = Map.get(params, "country_iso")

    changeset =
      params
      |> Geonames.change_postcode()
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:admin1_options, admin1_options(country_iso))
     |> assign_postcode_form(changeset)}
  end

  def handle_event("save-postcode", %{"postcode" => params}, socket) do
    if can_update?(socket) do
      save_postcode(socket, params)
    else
      write_forbidden(socket)
    end
  end

  def handle_event("save-postcode", _params, socket), do: write_failed(socket)

  def handle_event(
        "save-postcode-place",
        %{"id" => reference, "place_name" => place_name},
        socket
      )
      when is_binary(reference) and is_binary(place_name) do
    if can_update?(socket) do
      save_postcode_place(socket, reference, place_name)
    else
      write_forbidden(socket)
    end
  end

  def handle_event("save-postcode-place", _params, socket), do: write_failed(socket)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav="admin.geonames.postcode">
      <.page id="postcodes-index" class="space-y-5">
        <.header>
          Geonames Postcodes
          <:title_actions>
            <button
              type="button"
              id="postcodes-pin"
              data-nav-pin="nav-admin-geonames-postcode"
              title="Pin Postcodes to sidebar"
              aria-label="Pin Postcodes to sidebar"
              aria-pressed="false"
              class="grid size-6 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
            >
              <.icon name="bilimbi-pin" class="size-3.5" />
            </button>
          </:title_actions>
          <:actions>
            <.button
              :if={@can_update?}
              id="postcodes-new"
              type="button"
              variant="primary"
              phx-click="new-postcode"
            >
              <.icon name="hero-plus" class="size-4" /> New Postcode
            </.button>
          </:actions>
        </.header>

        <.card
          :if={@postcode_country_summaries != []}
          id="postcodes-country-summary"
          inner_class="p-0"
        >
          <div class="border-b border-line px-4 py-3">
            <h2 class="text-sm font-semibold text-ink">Postcodes by country</h2>
          </div>
          <.table
            id="postcodes-country-summary-rows"
            rows={@postcode_country_summaries}
            row_id={fn summary -> "postcode-country-#{summary.country_iso}" end}
            sort_by={@index_state.summary_sort_by}
            sort_dir={@index_state.summary_sort_dir}
            sort_event="sort-summary"
            framed={false}
          >
            <:col :let={summary} label="Country" sort="country_name" sort_id="postcodes-summary-sort-country">
              <span class="whitespace-nowrap text-ink">{summary.country_name}</span>
            </:col>
            <:col :let={summary} label="ISO" sort="country_iso" sort_id="postcodes-summary-sort-iso">
              <span class="whitespace-nowrap font-mono text-xs text-ink-muted">{summary.country_iso}</span>
            </:col>
            <:col :let={summary} label="Records" sort="record_count" sort_id="postcodes-summary-sort-count" align={:right}>
              <span class="whitespace-nowrap tabular-nums text-ink">{format_integer(summary.record_count)}</span>
            </:col>
          </.table>
        </.card>

        <.card id="postcodes-card" inner_class="p-0">
          <.form
            for={@filters_form}
            id="postcodes-filters"
            phx-change="filters"
            class="p-2 mb-2"
          >
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
              />
              <.input
                field={@filters_form[:search]}
                id="postcodes-search"
                type="search"
                phx-debounce="300"
                label="Search postcodes"
                label_class="sr-only"
                wrapper_class="mb-0"
                placeholder="Search by postcode, place name, or country..."
                class="block w-full rounded-lg border border-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20"
              />
            </div>
          </.form>

          <.table
            id="postcodes-table"
            rows={@streams.postcodes}
            row_id={fn {id, _postcode} -> id end}
            row_item={fn {_id, postcode} -> postcode end}
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
            framed={false}
            caption="Geonames postcodes"
          >
            <:col :let={postcode} label="Country" sort="country_name" sort_id="postcodes-sort-country">
              <div class="whitespace-nowrap text-ink-muted">
                <span class="font-mono text-xs">{postcode.country_iso}</span>
                <span class="ml-1">{postcode.country_name || postcode.country_iso}</span>
              </div>
            </:col>
            <:col :let={postcode} label="Postcode" sort="postcode" sort_id="postcodes-sort-postcode">
              <div class="flex items-center gap-1.5 whitespace-nowrap">
                <span class="font-medium tabular-nums text-ink">{postcode.postcode}</span>
                <span
                  :if={postcode.provenance == :operator}
                  class="rounded-md border border-line bg-brand-surface px-1 py-0.5 text-[0.6875rem] text-ink-muted"
                >
                  Local
                </span>
              </div>
            </:col>
            <:col :let={postcode} label="Place Name" sort="place_name" sort_id="postcodes-sort-place">
              <.inline_edit
                :if={@can_update?}
                id={"postcode-#{postcode.id}-place-name"}
                value={postcode.place_name}
                id_value={"#{postcode.id}|#{postcode.revision}"}
                save_event="save-postcode-place"
                name="place_name"
                label={"Edit place name for #{postcode.postcode}"}
              />
              <span :if={!@can_update?} class="whitespace-nowrap text-ink-muted">
                {postcode.place_name}
              </span>
            </:col>
            <:col :let={postcode} label="Admin1 Code" sort="admin1_code" sort_id="postcodes-sort-admin1">
              <span class="whitespace-nowrap tabular-nums text-ink-muted">{postcode.admin1_code || "—"}</span>
            </:col>
            <:col :let={postcode} label="Updated" sort="updated_at" sort_id="postcodes-sort-updated">
              <span class="whitespace-nowrap text-xs tabular-nums text-ink-muted">
                <.datetime id={"postcode-#{postcode.id}-updated"} value={postcode.updated_at} format={:date} />
              </span>
            </:col>
            <:action :let={postcode} :if={@can_update?}>
              <button
                type="button"
                id={"postcode-#{postcode.id}-edit"}
                phx-click="edit-postcode"
                phx-value-id={postcode.id}
                class="rounded-md px-1.5 py-0.5 text-xs text-link transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong"
              >
                Edit details
              </button>
            </:action>
            <:empty :if={@postcodes_page.entries == []}>
              No postcodes found.
            </:empty>
          </.table>

          <.pagination
            id="postcodes-pagination"
            page={@postcodes_page}
            page_sizes={@page_sizes}
            filters_form={@filters_form}
          />
        </.card>

        <div
          :if={@modal_action in [:new, :edit]}
          id="postcode-modal"
          class="fixed inset-0 z-40 flex items-start justify-center bg-ink/40 p-6"
        >
          <div class="mt-10 w-full max-w-2xl rounded-xl border border-line bg-surface p-6 shadow-sm">
            <h2 class="text-lg font-medium tracking-tight text-ink-strong">
              {if @modal_action == :new, do: "New Postcode", else: "Edit Postcode"}
            </h2>
            <p class="mt-1 text-xs text-ink-subtle">
              Local corrections survive future GeoNames country refreshes.
            </p>

            <.form
              :if={@postcode_form}
              for={@postcode_form}
              id="postcode-form"
              phx-change="validate-postcode"
              phx-submit="save-postcode"
              class="mt-4 space-y-4"
            >
              <div class="grid gap-x-4 sm:grid-cols-2">
                <.input
                  field={@postcode_form[:country_iso]}
                  id="postcode-country"
                  type="select"
                  label="Country"
                  prompt="Select country..."
                  options={country_options(@countries)}
                  required
                />
                <.input
                  field={@postcode_form[:postcode]}
                  id="postcode-code"
                  label="Postcode"
                  maxlength="20"
                  required
                />
                <.input
                  field={@postcode_form[:place_name]}
                  id="postcode-place-name"
                  label="Place Name"
                  maxlength="180"
                  required
                />
                <.input
                  field={@postcode_form[:admin1_code]}
                  id="postcode-admin1"
                  type="select"
                  label="Admin1 Division"
                  prompt="None"
                  options={@admin1_options}
                />
                <.input
                  field={@postcode_form[:latitude]}
                  id="postcode-latitude"
                  type="number"
                  step="0.0000001"
                  label="Latitude"
                />
                <.input
                  field={@postcode_form[:longitude]}
                  id="postcode-longitude"
                  type="number"
                  step="0.0000001"
                  label="Longitude"
                />
                <.input
                  field={@postcode_form[:accuracy]}
                  id="postcode-accuracy"
                  type="select"
                  label="Accuracy"
                  prompt="Unknown"
                  options={Enum.map(1..6, &{Integer.to_string(&1), &1})}
                />
              </div>

              <div class="mt-6 flex justify-end gap-2">
                <.button id="postcode-cancel" type="button" phx-click="close-postcode-modal">
                  Cancel
                </.button>
                <.button
                  id="postcode-save"
                  type="submit"
                  variant="primary"
                  phx-disable-with="Saving…"
                >
                  Save
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </.page>
    </Layouts.app>
    """
  end

  defp load_page(socket, state) do
    postcodes_page =
      Geonames.page_postcodes(%{
        search: state.search,
        page: state.page,
        page_size: state.per_page,
        sort_by: state.sort_by,
        sort_dir: state.sort_dir
      })

    postcode_country_summaries =
      Geonames.list_postcode_country_summaries(%{
        sort_by: state.summary_sort_by,
        sort_dir: state.summary_sort_dir
      })

    state = %{state | page: postcodes_page.page, per_page: postcodes_page.page_size}
    countries = Geonames.list_countries()

    socket
    |> assign(:page_title, "Geonames Postcodes")
    |> assign(:page_sizes, @page_sizes)
    |> assign(:postcodes_page, postcodes_page)
    |> assign(:postcode_country_summaries, postcode_country_summaries)
    |> assign(:countries, countries)
    |> assign(:postcode_rows, Map.new(postcodes_page.entries, &{&1.id, &1}))
    |> assign(
      :filters_form,
      to_form(%{"search" => state.search, "perPage" => state.per_page}, as: :filters)
    )
    |> assign(:index_state, state)
    |> stream(:postcodes, postcodes_page.entries, reset: true)
  end

  defp save_postcode(socket, params) do
    result =
      case socket.assigns.modal_action do
        :new ->
          Geonames.create_postcode(params)

        :edit ->
          Geonames.update_postcode(
            socket.assigns.editing_postcode_id,
            socket.assigns.editing_revision,
            params
          )

        _other ->
          {:error, :not_found}
      end

    case result do
      {:ok, postcode} ->
        message =
          if socket.assigns.modal_action == :new,
            do: "Postcode #{postcode.postcode} created.",
            else: "Postcode #{postcode.postcode} updated."

        {:noreply,
         socket
         |> close_postcode_modal()
         |> put_flash(:info, message)
         |> load_page(socket.assigns.index_state)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_postcode_form(socket, Map.put(changeset, :action, :insert))}

      {:error, :stale} ->
        {:noreply,
         socket
         |> close_postcode_modal()
         |> put_flash(
           :error,
           "Postcode changed while you were editing. Review the current values and try again."
         )
         |> load_page(socket.assigns.index_state)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> close_postcode_modal()
         |> put_flash(:error, "Postcode is no longer available.")
         |> load_page(socket.assigns.index_state)}
    end
  end

  defp save_postcode_place(socket, reference, place_name) do
    with [id, revision] <- String.split(to_string(reference), "|", parts: 2),
         {:ok, postcode} <- Geonames.update_postcode(id, revision, %{place_name: place_name}) do
      {:noreply,
       socket
       |> assign(:postcode_rows, Map.put(socket.assigns.postcode_rows, postcode.id, postcode))
       |> stream_insert(:postcodes, postcode)
       |> put_flash(:info, "Postcode #{postcode.postcode} updated.")}
    else
      {:error, %Ecto.Changeset{}} ->
        write_failed(socket)

      {:error, :stale} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Postcode changed elsewhere. Review the current value and try again."
         )
         |> load_page(socket.assigns.index_state)}

      _other ->
        write_failed(socket)
    end
  end

  defp can_update?(socket) do
    Authz.can(socket.assigns.current_scope.actor, @update_capability).allowed
  end

  defp write_forbidden(socket) do
    {:noreply,
     socket
     |> assign(:can_update?, false)
     |> close_postcode_modal()
     |> put_flash(:error, "You do not have permission to update postcodes.")}
  end

  defp write_failed(socket) do
    {:noreply,
     put_flash(socket, :error, "Postcode was not changed. Review the values and try again.")}
  end

  defp close_postcode_modal(socket) do
    socket
    |> assign(:modal_action, nil)
    |> assign(:editing_postcode_id, nil)
    |> assign(:editing_revision, nil)
    |> assign(:postcode_form, nil)
  end

  defp assign_postcode_form(socket, changeset) do
    assign(socket, :postcode_form, to_form(changeset, as: :postcode))
  end

  defp postcode_attrs(postcode) do
    postcode
    |> Map.take([
      :country_iso,
      :postcode,
      :place_name,
      :admin1_code,
      :latitude,
      :longitude,
      :accuracy
    ])
    |> Map.update(:admin1_code, nil, fn
      nil -> nil
      code -> if String.contains?(code, "."), do: code, else: "#{postcode.country_iso}.#{code}"
    end)
  end

  defp country_options(countries), do: Enum.map(countries, &{"#{&1.country} (#{&1.iso})", &1.iso})

  defp admin1_options(nil), do: []

  defp admin1_options(country_iso) do
    country_iso
    |> Geonames.list_admin1()
    |> Enum.map(&{"#{&1.name} (#{&1.code})", &1.code})
  end

  defp positive_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp positive_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _other -> :error
    end
  end

  defp positive_id(_id), do: :error

  defp state_from_params(params) do
    sort_by = normalize_sort(Map.get(params, "sortBy"))
    summary_sort_by = normalize_summary_sort(Map.get(params, "summarySortBy"))

    %{
      search: Map.get(params, "search", ""),
      page: parse_page(Map.get(params, "page")),
      per_page: normalize_page_size(Map.get(params, "perPage")),
      sort_by: sort_by,
      sort_dir: normalize_direction(Map.get(params, "sortDir"), sort_by),
      summary_sort_by: summary_sort_by,
      summary_sort_dir:
        normalize_summary_direction(Map.get(params, "summarySortDir"), summary_sort_by)
    }
  end

  defp next_sort(state, sort_by) do
    sort_by = normalize_sort(sort_by)

    %{
      state
      | page: 1,
        sort_by: sort_by,
        sort_dir:
          if(state.sort_by == sort_by,
            do: flip_direction(state.sort_dir),
            else: default_direction(sort_by)
          )
    }
  end

  defp next_summary_sort(state, sort_by) do
    sort_by = normalize_summary_sort(sort_by)

    %{
      state
      | summary_sort_by: sort_by,
        summary_sort_dir:
          if(
            state.summary_sort_by == sort_by,
            do: flip_direction(state.summary_sort_dir),
            else: default_summary_direction(sort_by)
          )
    }
  end

  defp postcodes_path(state) do
    ~p"/geonames/postcodes?#{%{search: state.search, page: state.page, perPage: state.per_page, sortBy: state.sort_by, sortDir: state.sort_dir, summarySortBy: state.summary_sort_by, summarySortDir: state.summary_sort_dir}}"
  end

  defp normalize_sort(sort_by) when sort_by in @sorts, do: sort_by
  defp normalize_sort(_sort_by), do: "country_name"

  defp normalize_summary_sort(sort_by) when sort_by in @summary_sorts, do: sort_by
  defp normalize_summary_sort(_sort_by), do: "country_name"

  defp normalize_direction(direction, _sort_by) when direction in ["asc", "desc"], do: direction
  defp normalize_direction(_direction, sort_by), do: default_direction(sort_by)

  defp normalize_summary_direction(direction, _sort_by) when direction in ["asc", "desc"],
    do: direction

  defp normalize_summary_direction(_direction, sort_by), do: default_summary_direction(sort_by)

  defp default_direction(sort_by), do: Map.get(@initial_directions, sort_by, "asc")

  defp default_summary_direction(sort_by),
    do: Map.get(@summary_initial_directions, sort_by, "asc")

  defp flip_direction("asc"), do: "desc"
  defp flip_direction(_direction), do: "asc"

  defp normalize_page_size(value) do
    value = parse_page(value)
    Enum.find(@page_sizes, List.last(@page_sizes), &(&1 >= value))
  end

  defp parse_page(value) when is_integer(value) and value > 0, do: value

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _other -> 1
    end
  end

  defp parse_page(_value), do: 1

  defp bounded_page(value, page) do
    page_number = parse_page(value)
    max(page.total_pages, 1) |> min(page_number) |> max(1)
  end
end
