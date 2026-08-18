defmodule Bilimbi.Base.UI.Web.ReferenceLive do
  @moduledoc """
  Live reference catalog for shared UI components and design tokens.

  Renders all components in `Bilimbi.Base.UI.Components` in their real states,
  documenting variants, anti-patterns, and Belimbing provenance paths under
  `resources/core/views/components/` and `resources/core/css/`.
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
     |> assign(:page_title, "UI Reference")
     |> assign(:sample_rows, @sample_rows)
     |> assign(:sample_form, to_form(sample_data, as: :sample))
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
     |> assign(:sample_datetime, ~U[2026-08-17 14:30:00Z])
     |> assign(:click_count, 0)}
  end

  @impl true
  def handle_event("test_click", _params, socket) do
    {:noreply, update(socket, :click_count, &(&1 + 1))}
  end
end
