defmodule Bilimbi.Base.Settings.Web.GroupLive do
  @moduledoc """
  Operator-editable settings, generated from what modules declare.

  Belimbing's `app/Base/Settings/Livewire/SettingsForm.php` is an abstract
  component that a concrete page subclasses to pin one group
  (`app/Base/System/Livewire/Settings/General.php` is twenty lines). Elixir has
  no subclassing to lean on, so the group is pinned by the route instead: the
  page is data-driven either way, and a second group page is a route entry and
  a title rather than a new module.

  The screen owns no rules. `Bilimbi.Base.Settings.Form` decides what a field
  is, whether a value is inherited, what clearing means and what a secret may
  show; this renders that and hands submissions back. Placing it in
  `base/settings` rather than in a module that declares settings is deliberate:
  a group is a rendezvous — `operator` today holds one setting from
  `base/authz`, and the page must not move house when a second module
  contributes to it.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Settings.Form

  # Belimbing titles a page from its group config. Bilimbi's groups are bare
  # ids, so the page carries its own copy -- the same information, declared
  # where it is used instead of alongside the settings.
  @pages %{
    "operator" => %{
      groups: ["operator"],
      title: "Operator Settings",
      subtitle: "Instance-wide settings contributed by installed modules.",
      nav: "admin.system.settings",
      capability: "base.settings.global.manage"
    }
  }

  @impl true
  def mount(_params, _session, socket) do
    page = Map.fetch!(@pages, "operator")

    {:ok,
     socket
     |> assign(:page, page)
     |> assign(:page_title, page.title)
     |> assign(:active_tab, hd(page.groups))
     |> load_fields()}
  end

  @impl true
  def handle_event("switch_tab", %{"group" => group}, socket) do
    if group in socket.assigns.page.groups do
      {:noreply, assign(socket, :active_tab, group)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save", params, socket) do
    submitted = Map.get(params, "settings", %{})

    case Form.save(submitted, socket.assigns.fields, scope(socket)) do
      {:ok, outcome} ->
        {:noreply,
         socket
         |> load_fields()
         |> put_flash(:info, saved_message(outcome))}

      {:error, key, message} ->
        # Nothing was written -- Form.save/3 plans before it writes and rolls
        # back on a persistence error -- so the form is redrawn from storage
        # rather than from the rejected submission.
        {:noreply,
         socket
         |> load_fields()
         |> put_flash(:error, "#{label_for(socket, key)}: #{message}")}
    end
  end

  @impl true
  def handle_event("restore_defaults", _params, socket) do
    {:ok, cleared} = Form.restore_defaults(socket.assigns.fields, scope(socket))

    {:noreply,
     socket
     |> load_fields()
     |> put_flash(:info, restored_message(cleared))}
  end

  # This page edits the global scope, which is what `operator` settings declare.
  # A user- or company-scoped page passes a `Settings.Scope` here instead; the
  # form resolves each field at the nearest scope its definition allows.
  defp scope(_socket), do: nil

  defp load_fields(socket) do
    fields =
      socket.assigns.page.groups
      |> Form.fields(scope(socket))
      |> Enum.filter(&authorized_field?(socket.assigns.current_scope, &1))

    assign(socket, :fields, fields)
  end

  defp authorized_field?(_current_scope, %{definition: %{capability: nil}}), do: true

  defp authorized_field?(current_scope, %{definition: %{capability: capability}}) do
    allowed?(current_scope, capability)
  end

  defp fields_in(fields, group) do
    Enum.filter(fields, &(&1.definition.editable == group))
  end

  defp label_for(socket, key) do
    case Enum.find(socket.assigns.fields, &(&1.key == key)) do
      nil -> key
      field -> field.definition.label
    end
  end

  # Say what happened, not "Settings saved". A save that cleared two overrides
  # and wrote none looks identical to a no-op otherwise, and clearing is the
  # operation users most often think has failed.
  defp saved_message(%{written: [], cleared: [], unchanged: _}), do: "No changes to save."

  defp saved_message(%{written: written, cleared: cleared}) do
    # Pair each phrase with its own verb before dropping the empty ones.
    # Zipping afterwards slides "cleared" onto whichever phrase survived, and
    # a save that cleared one override reports it as updated.
    [{count(written, "setting"), "updated"}, {count(cleared, "override"), "cleared"}]
    |> Enum.reject(fn {phrase, _verb} -> is_nil(phrase) end)
    |> Enum.map_join(", ", fn {phrase, verb} -> "#{phrase} #{verb}" end)
    |> Kernel.<>(".")
  end

  defp restored_message([]), do: "Nothing to restore; every setting is already inherited."

  defp restored_message(cleared),
    do: "#{count(cleared, "override")} cleared. Values now come from their defaults."

  defp count([], _noun), do: nil
  defp count([_one], noun), do: "1 #{noun}"
  defp count(many, noun), do: "#{length(many)} #{noun}s"

  defp source_note(%{overridden?: true}), do: nil
  defp source_note(%{source_scope: :global}), do: "Inherited from the default"
  defp source_note(%{source_scope: scope}), do: "Inherited from #{scope}"

  defp input_type(%{encrypted?: true}), do: "password"
  defp input_type(%{definition: %{type: type}}) when type in [:integer, :float], do: "number"
  defp input_type(_field), do: "text"

  defp boolean_field?(%{definition: %{type: :boolean}}), do: true
  defp boolean_field?(_field), do: false

  defp boolean_checked?(%{value: true}), do: true
  defp boolean_checked?(_field), do: false

  defp input_value(%{value: nil}), do: ""
  defp input_value(%{value: value}) when is_list(value), do: Enum.join(value, ", ")
  defp input_value(%{value: value}), do: to_string(value)
end
