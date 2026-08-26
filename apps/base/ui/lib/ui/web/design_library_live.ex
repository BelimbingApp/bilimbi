defmodule Bilimbi.Base.UI.Web.DesignLibraryLive do
  @moduledoc """
  Human review surface for the design Bilimbi currently uses.

  The development review shows production components and visible variations.
  Accepted choices are recorded separately in Design Spec.
  """

  use Bilimbi.Base.UI, :live_view

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
  ]

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
      "select_field" => "standard",
      "checkbox_field" => "true",
      "textarea_field" => "Multi-line sample content demonstrating textarea rendering.",
      "date_field" => "2026-08-17",
      "time_field" => "14:30"
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
     |> assign(:sample_rows, @sample_rows)
     |> assign(:sample_form, to_form(sample_data, as: :sample))
     |> assign(:pattern_form, to_form(%{"search" => ""}, as: :pattern))
     |> assign(
       :error_form,
       to_form(error_data, as: :error_sample, errors: [invalid_text: {"can't be blank", []}])
     )
     |> assign(:pagination_sample_page, %{
       page: 2,
       page_size: 25,
       total_pages: 5,
       total_entries: 120
     })
     |> assign(:pagination_sample_form, to_form(%{"perPage" => 25}, as: :filters))
     |> assign(:pattern_pagination_form, to_form(%{"perPage" => 25}, as: :pattern_filters))
     |> assign(:sample_datetime, ~U[2026-08-17 14:30:00Z])
     |> assign(:inline_value, "Editable entity value")
     |> assign(:click_count, 0)}
  end

  @impl true
  def handle_event("test_click", _params, socket) do
    {:noreply, update(socket, :click_count, &(&1 + 1))}
  end

  @impl true
  def handle_event("preview-inline-edit", %{"value" => value}, socket) do
    {:noreply,
     socket
     |> assign(:inline_value, value)
     |> put_flash(:info, gettext("Preview value updated."))}
  end

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
      gettext("Compare current UI choices, then review every shared component in use."),
      gettext("6 decisions"),
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
