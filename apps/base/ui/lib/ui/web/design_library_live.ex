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
                      updated_at: ~U[2026-08-17 12:00:00Z]
                    }
                  end)

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
     |> assign_preview_page(:sample, 1, 25)
     |> assign_preview_page(:pattern, 1, 25)
     |> assign(:sample_datetime, ~U[2026-08-17 14:30:00Z])
     |> assign(:inline_value, "Editable entity value")
     |> assign(:click_count, 0)}
  end

  @impl true
  def handle_event("test_click", _params, socket) do
    {:noreply, update(socket, :click_count, &(&1 + 1))}
  end

  @impl true
  def handle_event("sample_change", %{"sample" => sample_data}, socket) do
    {:noreply, assign(socket, :sample_form, to_form(sample_data, as: :sample))}
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
      :sample -> assign(socket, sample_rows: rows, sample_page: data, sample_page_form: form)
      :pattern -> assign(socket, pattern_rows: rows, pattern_page: data, pattern_page_form: form)
    end
  end

  defp preview_rows(:sample, _socket), do: @sample_rows

  defp preview_rows(:pattern, socket) do
    search = socket.assigns.pattern_form[:search].value |> String.trim() |> String.downcase()

    Enum.filter(
      @sample_rows,
      &String.contains?(String.downcase(&1.name <> " " <> &1.code), search)
    )
  end

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
