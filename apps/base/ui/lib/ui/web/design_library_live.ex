defmodule Bilimbi.Base.UI.Web.DesignLibraryLive do
  @moduledoc """
  Human review surface for the design Bilimbi currently uses.

  Components shows the production catalogue. Accepted choices are recorded in
  Design Spec.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Menu.Item

  # The Navigation entry renders `Layouts.nav_branch/1` -- the shell's own rail
  # -- over a fixed tree, so the card cannot drift from what the sidebar does.
  # Ids are namespaced away from the real menu because both trees share the page.
  @nav_example [
    %{
      item: %Item{
        id: "example.companies",
        label: "Companies",
        icon: "building-office-2",
        route: "/system/design-library/components"
      },
      children: []
    },
    %{
      item: %Item{id: "example.system", label: "System", icon: "cog-6-tooth"},
      children: [
        %{
          item: %Item{
            id: "example.system.design-library",
            label: "Design Library",
            icon: "paint-brush",
            route: "/system/design-library/components"
          },
          children: []
        }
      ]
    }
  ]

  @nav_example_active "example.system.design-library"

  @sample_rows [
                 %{
                   id: 1,
                   name: "Acme Holdings",
                   code: "acme",
                   status: "active",
                   kind: :success,
                   updated_at: ~U[2026-08-17 12:00:00Z]
                 },
                 %{
                   id: 2,
                   name: "Globex Corporation",
                   code: "globex",
                   status: "pending",
                   kind: :warning,
                   updated_at: ~U[2026-08-16 15:30:00Z]
                 },
                 %{
                   id: 3,
                   name: "Initech LLC",
                   code: "initech",
                   status: "suspended",
                   kind: :danger,
                   updated_at: ~U[2026-08-15 09:15:00Z]
                 }
               ] ++
                 (for id <- 4..120 do
                    %{
                      id: id,
                      name: "Example Company #{id}",
                      code: "example-#{id}",
                      status: "active",
                      kind: :success,
                      updated_at: DateTime.add(~U[2026-08-14 12:00:00Z], 4 - id, :day)
                    }
                  end)

  # The canonical table sorts the way `/users` does: the column button pushes
  # a string key, the direction is `"asc"`/`"desc"`, a repeated click flips
  # it, and the timestamp column opens newest first.
  @sample_sorts %{
    "name" => :name,
    "code" => :code,
    "status" => :status,
    "updated_at" => :updated_at
  }
  @sample_initial_directions %{"updated_at" => "desc"}
  @sample_default_sort "name"

  @impl true
  def mount(_params, _session, socket) do
    mount_area(:theme, socket)
  end

  @doc false
  def mount_area(area, socket) do
    {area_title, area_description, area_stage, active_nav} = area_details(area)

    sample_data = %{
      "text_field" => "Sample text value",
      "search_field" => "Search query",
      "email_field" => "hello@example.com",
      "tel_field" => "+60 12-345 6789",
      "url_field" => "https://bilimbi.test",
      "number_field" => "25",
      "password_field" => "secret-value",
      "api_key_field" => "sk-sample-0000",
      "select_field" => "standard",
      "roles" => ["admin", "reviewer"],
      "required_roles" => ["admin"],
      "plain_roles" => [],
      "example_interests" => ["platform"],
      "checkbox_field" => "true",
      "radio_field" => "system",
      "textarea_field" => "Multi-line sample content demonstrating textarea rendering.",
      "date_field" => "2026-08-17",
      "time_field" => "14:30",
      "datetime_field" => "2026-08-17T14:30",
      "month_field" => "2026-08",
      "week_field" => "2026-W34"
    }

    error_data = %{
      "invalid_text" => ""
    }

    {:ok,
     socket
     |> assign(:page_title, "#{area_title} · Design Library")
     |> assign(:area, area)
     |> assign(:area_title, area_title)
     |> assign(:area_description, area_description)
     |> assign(:area_stage, area_stage)
     |> assign(:active_nav, active_nav)
     |> assign(:nav_example, @nav_example)
     |> assign(:nav_example_active, @nav_example_active)
     |> assign(:sample_form, to_form(sample_data, as: :sample))
     |> assign(:pattern_form, to_form(%{"search" => ""}, as: :pattern))
     |> assign(
       :error_form,
       to_form(error_data, as: :error_sample, errors: [invalid_text: {"can't be blank", []}])
     )
     |> stream_configure(:sample_rows, dom_id: &"sample-row-#{&1.id}")
     |> assign(:sample_sort, sort_state(@sample_default_sort))
     |> assign(:sample_filter_form, to_form(%{"search" => ""}, as: :sample_filters))
     |> assign(:sample_id_rows, Enum.take(@sample_rows, 5))
     |> assign_preview_page(:sample, 1, 25)
     |> assign_preview_page(:pattern, 1, 25)
     |> assign(:sample_datetime, ~U[2026-08-17 14:30:00Z])
     |> assign(:inline_value, "Editable entity value")
     |> assign(:click_count, 0)
     |> assign(:modal_width, nil)
     |> assign(
       :modal_form,
       to_form(%{"name" => "Example Sdn Bhd", "code" => "EX-01"}, as: :example)
     )
     |> assign(
       :filter_toolbar_full_form,
       to_form(
         %{
           "search" => "",
           "status" => "",
           "kind" => "",
           "start_date" => "",
           "end_date" => ""
         },
         as: :toolbar_full
       )
     )}
  end

  @impl true
  def handle_event("open-modal", params, socket) do
    width = if params["width"] == "wide", do: :wide, else: :narrow
    {:noreply, assign(socket, :modal_width, width)}
  end

  @impl true
  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, :modal_width, nil)}
  end

  @impl true
  def handle_event("test_click", _params, socket) do
    {:noreply, update(socket, :click_count, &(&1 + 1))}
  end

  @impl true
  def handle_event("sample_change", %{"sample" => sample_data}, socket) do
    {:noreply, assign(socket, :sample_form, to_form(sample_data, as: :sample))}
  end

  def handle_event("filter-toolbar-preview", %{"toolbar_full" => toolbar_data}, socket) do
    {:noreply,
     assign(socket, :filter_toolbar_full_form, to_form(toolbar_data, as: :toolbar_full))}
  end

  @impl true
  def handle_event("preview-inline-edit", %{"value" => value}, socket) do
    {:noreply,
     socket
     |> assign(:inline_value, value)
     |> put_flash(:info, gettext("Preview value updated."))}
  end

  def handle_event("preview-company", %{"id" => id}, socket) do
    case Enum.find(@sample_rows, &(Integer.to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      row ->
        {:noreply,
         put_flash(socket, :info, "Example only: #{row.name} · #{row.code} · #{row.status}")}
    end
  end

  def handle_event("sample-sort", %{"sort" => requested_sort}, socket) do
    {:noreply,
     socket
     |> assign(:sample_sort, next_sort(socket.assigns.sample_sort, requested_sort))
     |> assign_preview_page(:sample, 1, socket.assigns.sample_page.page_size)}
  end

  def handle_event("sample-search", %{"sample_filters" => %{"search" => search}}, socket) do
    {:noreply, assign_sample_search(socket, search)}
  end

  def handle_event("sample-clear-search", _params, socket) do
    {:noreply, assign_sample_search(socket, "")}
  end

  def handle_event(event, %{"page" => page}, socket)
      when event in ["sample-page", "pattern-page"] do
    {preview, current} = preview_page(event, socket)

    {:noreply,
     assign_preview_page(socket, preview, positive_integer(page, current.page), current.page_size)}
  end

  def handle_event(event, %{"filters" => %{"perPage" => value}}, socket)
      when event in ["sample-page-size", "pattern-page-size"] do
    {preview, current} = preview_page(event, socket)
    page_size = positive_integer(value, current.page_size)
    page_size = if page_size in [25, 50, 100, 300], do: page_size, else: current.page_size
    {:noreply, assign_preview_page(socket, preview, 1, page_size)}
  end

  def handle_event("pattern-search", %{"pattern" => %{"search" => search}}, socket) do
    {:noreply,
     socket
     |> assign(:pattern_form, to_form(%{"search" => search}, as: :pattern))
     |> assign_preview_page(:pattern, 1, socket.assigns.pattern_page.page_size)}
  end

  defp assign_sample_search(socket, search) do
    socket
    |> assign(:sample_filter_form, to_form(%{"search" => search}, as: :sample_filters))
    |> assign_preview_page(:sample, 1, socket.assigns.sample_page.page_size)
  end

  defp preview_page(event, socket) when event in ["sample-page", "sample-page-size"],
    do: {:sample, socket.assigns.sample_page}

  defp preview_page(_event, socket), do: {:pattern, socket.assigns.pattern_page}

  defp assign_preview_page(socket, preview, requested_page, page_size) do
    rows = preview_rows(preview, socket)
    total_entries = length(rows)
    total_pages = ceil(total_entries / page_size)
    page = requested_page |> max(1) |> min(max(total_pages, 1))

    data = %{
      page: page,
      page_size: page_size,
      total_pages: total_pages,
      total_entries: total_entries
    }

    rows = Enum.slice(rows, (page - 1) * page_size, page_size)
    form = to_form(%{"perPage" => page_size}, as: :filters)

    case preview do
      :sample ->
        socket
        |> assign(sample_page: data, sample_page_form: form)
        |> stream(:sample_rows, rows, reset: true)

      :pattern ->
        assign(socket, pattern_rows: rows, pattern_page: data, pattern_page_form: form)
    end
  end

  defp preview_rows(:sample, socket) do
    %{sort_by: sort_by, sort_dir: sort_dir} = socket.assigns.sample_sort
    field = Map.fetch!(@sample_sorts, sort_by)
    direction = direction_atom(sort_dir)

    sorter =
      if field == :updated_at,
        do: {direction, DateTime},
        else: direction

    rows = matching_rows(socket.assigns.sample_filter_form)

    Enum.sort_by(rows, &Map.fetch!(&1, field), sorter)
  end

  defp preview_rows(:pattern, socket), do: matching_rows(socket.assigns.pattern_form)

  defp matching_rows(form) do
    search = form[:search].value |> String.trim() |> String.downcase()

    Enum.filter(
      @sample_rows,
      &String.contains?(String.downcase(&1.name <> " " <> &1.code), search)
    )
  end

  defp sort_state(sort_by), do: %{sort_by: sort_by, sort_dir: default_direction(sort_by)}

  defp next_sort(state, requested_sort) when is_map_key(@sample_sorts, requested_sort) do
    %{
      sort_by: requested_sort,
      sort_dir:
        if(state.sort_by == requested_sort,
          do: flip_direction(state.sort_dir),
          else: default_direction(requested_sort)
        )
    }
  end

  defp next_sort(state, _requested_sort), do: state

  defp default_direction(sort_by), do: Map.get(@sample_initial_directions, sort_by, "asc")
  defp flip_direction("asc"), do: "desc"
  defp flip_direction(_direction), do: "asc"

  defp direction_atom("desc"), do: :desc
  defp direction_atom(_direction), do: :asc

  defp positive_integer(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> fallback
    end
  end

  defp positive_integer(_value, fallback), do: fallback

  defp area_details(:theme) do
    {
      gettext("Theme"),
      gettext("The visual foundations now used throughout Bilimbi."),
      gettext("Development review"),
      "admin.system.design-library.theme"
    }
  end

  defp area_details(:components) do
    {
      gettext("Components"),
      gettext("Choose a component family, then review its current behaviour and states."),
      gettext("Current library"),
      "admin.system.design-library.components"
    }
  end

  defp area_details(:graphic) do
    {
      gettext("Graphic"),
      gettext("The Bilimbi mark and icons now used across the product."),
      gettext("Development review"),
      "admin.system.design-library.graphic"
    }
  end

  defp area_details(:design_spec) do
    {
      gettext("Design Spec"),
      gettext("The design choices accepted for Bilimbi."),
      gettext("Accepted design"),
      "admin.system.design-library.design-spec"
    }
  end
end
