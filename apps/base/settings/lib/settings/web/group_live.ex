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
     |> assign(:pending_restore, nil)
     |> load_fields()}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => group}, socket) do
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

  # Restoring confirms through the shared dialog: the request holds the
  # overrides the dialog counts, and `restore_defaults` acts only once one is
  # held, so what was confirmed is what runs. With nothing overridden there is
  # nothing to confirm, and the page says so instead of asking.
  @impl true
  def handle_event("request_restore", _params, socket) do
    case Enum.filter(socket.assigns.fields, & &1.overridden?) do
      [] ->
        {:noreply, put_flash(socket, :info, restored_message([]))}

      overridden ->
        {:noreply, socket |> clear_flash() |> assign(:pending_restore, overridden)}
    end
  end

  @impl true
  def handle_event("cancel_restore", _params, socket) do
    {:noreply, assign(socket, :pending_restore, nil)}
  end

  @impl true
  def handle_event("restore_defaults", _params, %{assigns: %{pending_restore: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("restore_defaults", _params, socket) do
    {:ok, cleared} = Form.restore_defaults(socket.assigns.fields, scope(socket))

    {:noreply,
     socket
     |> assign(:pending_restore, nil)
     |> load_fields()
     |> put_flash(:success, restored_message(cleared))}
  end

  # This page edits the global scope, which is what `operator` settings declare.
  # A user- or company-scoped page passes a `Settings.Scope` here instead; the
  # form resolves each field at the nearest scope its definition allows.
  defp scope(_socket), do: nil

  # A field the actor may not see is withheld here, not by the form, so the
  # page also knows what it withheld. A group left empty by that filter is
  # otherwise indistinguishable from one no module contributes to, and the
  # empty state would blame the modules for what is really a permission.
  defp load_fields(socket) do
    {fields, withheld} =
      socket.assigns.page.groups
      |> Form.fields(scope(socket))
      |> Enum.split_with(&authorized_field?(socket.assigns.current_scope, &1))

    socket
    |> assign(:fields, fields)
    |> assign(:withheld_capabilities, withheld_capabilities(withheld))
  end

  # Per group, the capabilities the withheld fields require, in the key form
  # the Roles and Capabilities pages already use to name them.
  defp withheld_capabilities(withheld) do
    withheld
    |> Enum.group_by(& &1.definition.editable, & &1.definition.capability)
    |> Map.new(fn {group, capabilities} ->
      {group, capabilities |> Enum.uniq() |> Enum.sort()}
    end)
  end

  defp authorized_field?(_current_scope, %{definition: %{capability: nil}}), do: true

  defp authorized_field?(current_scope, %{definition: %{capability: capability}}) do
    allowed?(current_scope, capability)
  end

  defp fields_in(fields, group) do
    Enum.filter(fields, &(&1.definition.editable == group))
  end

  defp withheld_in(withheld_capabilities, group), do: Map.get(withheld_capabilities, group, [])

  # The action `<.empty_state forbidden>` completes into "You do not have
  # permission to ...". Every setting in the group needs exactly one
  # capability, so the sentence names each one the actor lacks.
  defp withheld_wording([capability]),
    do: "see the settings in this group, each of which needs #{capability}"

  defp withheld_wording(capabilities) do
    {rest, [last]} = Enum.split(capabilities, -1)

    "see the settings in this group; each setting needs its own permission, and this group uses #{Enum.join(rest, ", ")} and #{last}"
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

  # "Shown", not "every setting": restore only reaches the fields this account
  # may see, and a withheld field may still hold an override.
  defp restored_message([]), do: "Nothing to restore; every setting shown is already inherited."

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
