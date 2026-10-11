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

  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Form
  alias Bilimbi.Base.Settings.Scope

  # Belimbing titles a page from its group config. Bilimbi's groups are bare
  # ids, so the page carries its own copy -- the same information, declared
  # where it is used instead of alongside the settings.
  @pages %{
    "operator" => %{
      groups: ["operator"],
      title: "Operator Settings",
      subtitle: "Settings contributed by installed modules.",
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
     |> assign(:pending_reveal, nil)
     |> assign(:setting_scope, nil)
     |> assign(:scope_archived?, false)
     |> assign(:scope_form, scope_form(nil))
     |> assign(
       :can_manage_company,
       allowed?(socket.assigns.current_scope, "base.settings.company.manage")
     )
     |> assign(:companies, company_service().companies(socket.assigns.current_scope))
     |> load_fields()}
  end

  @impl true
  def handle_event("switch_scope", %{"scope" => %{"company_id" => "global"}}, socket) do
    {:noreply, select_scope(socket, nil)}
  end

  def handle_event("switch_scope", %{"scope" => %{"company_id" => id}}, socket)
      when is_binary(id) do
    with {id, ""} when id > 0 <- Integer.parse(id),
         {:ok, scope} <- company_service().authorize(socket.assigns.current_scope, id) do
      {:noreply, select_scope(socket, scope)}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You do not have permission to manage this company's settings."
         )}
    end
  end

  def handle_event("switch_scope", _params, socket) do
    {:noreply, put_flash(socket, :error, "Choose an available settings scope.")}
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
  def handle_event("request_secret_reveal", %{"key" => key}, socket) do
    field = Enum.find(socket.assigns.fields, &(&1.key == key and &1.encrypted?))

    if scope_authorized?(socket) && field && field.value == Form.secret_mask() &&
         secret_service().available?(socket.assigns.current_scope) do
      {:noreply, assign(socket, :pending_reveal, key)}
    else
      # Even a forged request is recorded as a refused reveal by the host edge.
      secret_service().reveal(socket.assigns.current_scope, key, scope(socket), "")
      {:noreply, put_flash(socket, :error, "Stored value cannot be shown.")}
    end
  end

  @impl true
  def handle_event("cancel_secret_reveal", _params, socket) do
    {:noreply, assign(socket, :pending_reveal, nil)}
  end

  @impl true
  def handle_event("confirm_secret_reveal", %{"reveal" => %{"password" => password}}, socket) do
    case socket.assigns.pending_reveal do
      nil ->
        {:noreply, socket}

      key ->
        result =
          secret_service().reveal(socket.assigns.current_scope, key, scope(socket), password)

        case result do
          {:ok, value} ->
            field = Enum.find(socket.assigns.fields, &(&1.key == key))
            id = "input-#{String.replace(key, ".", "-")}"

            {:noreply,
             socket
             |> assign(:pending_reveal, nil)
             |> push_event("secret:reveal", %{
               id: id,
               value: value,
               duration_ms: field.definition.reveal_duration_ms
             })}

          {:error, :throttled} ->
            {:noreply, put_flash(socket, :error, "Too many attempts. Try again later.")}

          {:error, :invalid_password} ->
            {:noreply, put_flash(socket, :error, "Password was not accepted.")}

          {:error, :audit_unavailable} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "The reveal could not be recorded, so the value was not shown. Try again later."
             )}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:pending_reveal, nil)
             |> put_flash(:error, "This stored value cannot be shown.")}
        end
    end
  end

  @impl true
  def handle_event("save", params, socket) do
    case scope_writable(socket) do
      :ok ->
        save(params, load_fields(socket))

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
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
    case scope_writable(socket) do
      :ok ->
        restore(socket)

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:pending_restore, nil)
         |> put_flash(:error, message)}
    end
  end

  @impl true
  def handle_event("request_clear", %{"key" => key}, socket) do
    case Enum.find(socket.assigns.fields, &(&1.key == key and &1.overridden?)) do
      nil -> {:noreply, socket}
      field -> {:noreply, assign(socket, :pending_restore, [field])}
    end
  end

  defp select_scope(socket, scope) do
    groups = if scope, do: company_groups(), else: @pages["operator"].groups

    socket
    |> assign(:setting_scope, scope)
    |> assign(:scope_archived?, scope_archived?(socket, scope))
    |> assign(:scope_form, scope_form(scope))
    |> assign(:page, %{socket.assigns.page | groups: groups})
    |> assign(:active_tab, List.first(groups))
    |> assign(:pending_restore, nil)
    |> assign(:pending_reveal, nil)
    |> clear_flash()
    |> load_fields()
    |> select_available_group()
  end

  defp select_available_group(socket) do
    group =
      Enum.find(socket.assigns.page.groups, List.first(socket.assigns.page.groups), fn group ->
        fields_in(socket.assigns.fields, group) != []
      end)

    assign(socket, :active_tab, group)
  end

  defp company_groups do
    Settings.definitions()
    |> Map.values()
    |> Enum.filter(&(:company in &1.scopes and is_binary(&1.editable)))
    |> Enum.map(& &1.editable)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp save(params, socket) do
    submitted = Map.get(params, "settings", %{})

    case Form.save(
           submitted,
           socket.assigns.fields,
           scope(socket),
           socket.assigns.current_scope.scope
         ) do
      # The kind follows the outcome: a save that wrote or cleared nothing
      # informs, one that changed storage confirms.
      {:ok, %{written: [], cleared: []} = outcome} ->
        {:noreply,
         socket
         |> load_fields()
         |> put_flash(:info, saved_message(outcome))}

      {:ok, outcome} ->
        {:noreply,
         socket
         |> load_fields()
         |> put_flash(:success, saved_message(outcome))}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, "You do not have permission to manage platform settings.")}

      {:error, key, message} ->
        # Nothing was written -- Form.save/4 plans before it writes and rolls
        # back on a persistence error -- so the form is redrawn from storage
        # rather than from the rejected submission.
        {:noreply,
         socket
         |> load_fields()
         |> put_flash(:error, "#{label_for(socket, key)}: #{message}")}
    end
  end

  defp restore(socket) do
    # Recheck definition permissions and act only on the fields confirmed.
    held_keys = Enum.map(socket.assigns.pending_restore, & &1.key)
    socket = load_fields(socket)
    fields = Enum.filter(socket.assigns.fields, &(&1.key in held_keys))

    case Form.restore_defaults(fields, scope(socket), socket.assigns.current_scope.scope) do
      {:ok, cleared} ->
        {:noreply,
         socket
         |> assign(:pending_restore, nil)
         |> load_fields()
         |> put_flash(if(cleared == [], do: :info, else: :success), restored_message(cleared))}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> assign(:pending_restore, nil)
         |> put_flash(:error, "You do not have permission to manage platform settings.")}
    end
  end

  defp scope_form(scope) do
    to_form(%{"company_id" => if(scope, do: to_string(scope.id), else: "global")}, as: :scope)
  end

  defp scope(socket), do: socket.assigns.setting_scope

  defp scope_authorized?(%{assigns: %{setting_scope: nil}}), do: true

  defp scope_authorized?(socket) do
    match?({:ok, _}, company_service().authorize(socket.assigns.current_scope, scope(socket).id))
  end

  # A write asks twice: may the person manage this company's settings, and
  # may the company be written at all. An archived company is read-only, and
  # the page says that rather than blaming a permission.
  defp scope_writable(%{assigns: %{setting_scope: nil}}), do: :ok

  defp scope_writable(socket) do
    cond do
      not scope_authorized?(socket) ->
        {:error, "You do not have permission to manage this company's settings."}

      company_service().writable(socket.assigns.current_scope, scope(socket).id) != :ok ->
        {:error, "This company is archived and read-only, so its settings were not changed."}

      true ->
        :ok
    end
  end

  # Presentation only: the page hides its save and clear controls and says
  # why. Each write still asks `scope_writable/1`.
  defp scope_archived?(_socket, nil), do: false

  defp scope_archived?(socket, scope),
    do: company_service().writable(socket.assigns.current_scope, scope.id) != :ok

  defp company_service do
    Application.fetch_env!(:bilimbi_base_settings, :company_scope_service)
  end

  # A field the actor may not see is withheld here, not by the form, so the
  # page also knows what it withheld. A group left empty by that filter is
  # otherwise indistinguishable from one no module contributes to, and the
  # empty state would blame the modules for what is really a permission.
  defp load_fields(socket) do
    {fields, withheld} =
      socket.assigns.page.groups
      |> Form.fields(scope(socket))
      |> Enum.filter(&(is_nil(scope(socket)) or :company in &1.definition.scopes))
      |> Enum.split_with(&authorized_field?(socket.assigns.current_scope, &1))

    socket
    |> assign(:fields, fields)
    |> assign(:can_reveal_secret, secret_service().available?(socket.assigns.current_scope))
    |> assign(:withheld_capabilities, withheld_capabilities(withheld))
  end

  defp secret_service do
    Application.fetch_env!(:bilimbi_base_settings, :secret_reveal_service)
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

  defp group_label(group) do
    group |> String.replace([".", "_"], " ") |> String.capitalize()
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
    do: "#{count(cleared, "override")} cleared. Values now come from what they inherit."

  defp count([], _noun), do: nil
  defp count([_one], noun), do: "1 #{noun}"
  defp count(many, noun), do: "#{length(many)} #{noun}s"

  defp source_note(%{overridden?: true}, _scope), do: nil

  defp source_note(%{source_scope: :global} = field, %Scope{type: :company}) do
    if :global in field.definition.scopes and Settings.overridden?(field.key),
      do: "Inherited from global",
      else: "Inherited from the default"
  end

  defp source_note(%{source_scope: :global}, _scope), do: "Inherited from the default"
  defp source_note(%{source_scope: scope}, _selected_scope), do: "Inherited from #{scope}"

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
