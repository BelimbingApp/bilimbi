defmodule Bilimbi.Base.System.Web.LocalizationLive do
  @moduledoc """
  Authorized installation locale selection and provenance.

  Base System owns the operator route and presentation. Base Locale remains the
  policy owner: this LiveView renders its immutable catalogue, persists only
  through its public global API, and never reaches into Core Company bootstrap
  data. Bootstrap provenance is read-only here, matching pinned Belimbing.

  The host re-checks the route capability before every event; the save
  re-asks for the same grant through `LiveAuthorization.authorize_event/2`
  so the refusal names this page's operation, because the capability shown
  when the LiveView mounted is presentation state, not an authorization
  decision.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz.LiveAuthorization
  alias Bilimbi.Base.Locale

  @manage_capability "admin.system.localization.manage"

  @source_labels %{
    "declared_default" => "Using declared default",
    "manual" => "Selected manually",
    "platform_operator_address" => "Inferred from platform-operator company address"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Language & Region")
     |> assign(:active_nav, "admin.system.localization")
     |> assign(:locale_options, locale_options())
     |> load_locale()}
  end

  @impl true
  def handle_event("save", params, socket) do
    case LiveAuthorization.authorize_event(socket, @manage_capability) do
      {:ok, socket} -> save(params, socket)
      {:denied, socket} -> write_forbidden(socket)
    end
  end

  defp save(%{"localization" => %{"locale" => locale}}, socket) do
    if Locale.supports?(locale) do
      case Locale.put(nil, locale) do
        {:ok, _locale} ->
          {:noreply,
           socket
           |> load_locale()
           |> put_flash(:success, "Installation locale saved.")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not save the installation locale.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Choose a supported locale.")}
    end
  end

  defp save(_params, socket) do
    {:noreply, put_flash(socket, :error, "Choose a supported locale.")}
  end

  defp write_forbidden(socket) do
    {:noreply,
     put_flash(socket, :error, "You do not have permission to manage the installation locale.")}
  end

  defp load_locale(socket) do
    resolved = Locale.resolve(nil)

    assign(socket,
      form: to_form(%{"locale" => resolved.locale}, as: :localization),
      resolved: resolved,
      locale_label: Locale.label(resolved.locale),
      source_label: Map.fetch!(@source_labels, resolved.source),
      inferred_country: resolved.inferred_country || "Not recorded",
      shared_ui_catalogues: shared_ui_catalogues()
    )
  end

  defp locale_options do
    Locale.supported_locales()
    |> Enum.map(fn {code, %{label: label}} -> {"#{label} (#{code})", code} end)
    |> Enum.sort()
  end

  defp shared_ui_catalogues do
    Bilimbi.Base.UI.Gettext
    |> Gettext.known_locales()
    |> Enum.sort()
    |> Enum.join(", ")
  end
end
