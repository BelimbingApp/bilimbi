defmodule Bilimbi.Base.UI.WriteHandlerGuardTest do
  @moduledoc """
  A write-shaped `handle_event/3` must be refused when the actor lacks the
  write capability. Hiding the button in the template is not a guard: #376
  found ten write handlers on the company show page reachable by any actor
  holding only `admin.company.view`, because `{@can_update?}` hid the controls
  and nothing else refused the event. There is no reason to think that page
  was special, and review demonstrably did not catch it.

  ## What counts as covered

  A **deny clause**: a `handle_event/3` clause whose socket pattern matches
  `%{assigns: %{can_*?: false}}`. Two shapes are in use and both are read:

      # per-event (company department types)
      def handle_event("delete", _params, %{assigns: %{can_delete?: false}} = socket),
        do: write_forbidden(socket)

      # catch-all over a declared list (company show)
      @write_events ~w(save_details unlink_address ...)
      def handle_event(event, _params, %{assigns: %{can_update?: false}} = socket)
          when event in @write_events,
          do: write_forbidden(socket)

  The attribute is resolved from the module's own literal `~w`/list definition,
  so adding a write event without adding it to `@write_events` leaves it
  uncovered — that is the point.

  ## The opt-out

      # Sort reorders the reading of the list; it writes nothing.
      @write_guard_opt_out ~w(sort_subordinates)

  `@write_guard_opt_out` is for events that are write-shaped **by name only**
  (sort/filter/UI-state toggles) and for screens whose route mounts under the
  write capability itself, so there is no weaker capability to refuse. Every
  entry needs a reason comment next to the attribute; a lie here is greppable
  and review's job, not the test's.

  ## Derived, not a fixture

  The file set is discovered by content (`handle_event/3` definitions under
  `web/` trees and `apps/web`), the event names come from the parsed AST, and
  coverage comes from the module's own clauses and attributes. Nothing here
  mirrors a hand-written list of modules — `workspace_boundary_test.exs` is
  the cautionary case: it mirrored what it checked, caught nothing, and
  serialised every new module through one file.

  `@tracked` is acknowledged debt, not endorsement: each entry is an
  unguarded write-shaped event that existed when this test landed. Fixing a
  module — guard clause or opt-out — **fails the test until its entry is
  deleted**, which is what keeps the list from becoming wallpaper.

  ## What this does not check

  Route-level gating is invisible here: a screen mounted only under its write
  capability is covered in truth, and its events still appear as offenders —
  that is what the opt-out with a reason is for. `validate`/`change` form-input
  events are not write-shaped and are not checked. The assign name must start
  with `can_` and end with `?`; a differently named deny assign fails this test
  and either gets renamed or the convention grows deliberately.
  """

  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)

  # Write-shaped by prefix. The list is the definition: extending it is a
  # deliberate act recorded in this file, not something that happens by
  # accident. Add a verb when a write event with that shape lands.
  @write_verbs ~w(
    save
    add
    remove
    delete
    create
    update
    toggle
    unlink
    link
    attach
    detach
    move
    reorder
    mark
    assign
    deny
    grant
    restore
    run
  )

  # Write-shaped in full: bare verbs and one-off write names in use.
  @exact_writes ~w(save delete create duplicate terminate designate)

  @opt_out_attribute :write_guard_opt_out

  # Acknowledged debt from when this test landed. Each {module_path, event}
  # is an unguarded write-shaped handler. Delete the entry in the same change
  # that guards or opts out the event.
  @tracked [
    {"apps/base/audit/lib/audit/web/actions_live.ex", "toggle_retain"},
    {"apps/base/authz/lib/authz/web/role_create_live.ex", "save"},
    {"apps/base/session/lib/session/web/live/index_live.ex", "terminate"},
    {"apps/base/settings/lib/settings/web/group_live.ex", "restore_defaults"},
    {"apps/base/settings/lib/settings/web/group_live.ex", "save"},
    {"apps/base/tenancy/lib/tenancy/web/live/tenants_live.ex", "create"},
    {"apps/core/address/lib/address/web/create_live.ex", "save"},
    {"apps/core/address/lib/address/web/index_live.ex", "delete"},
    {"apps/core/address/lib/address/web/show_live.ex", "save_details"},
    {"apps/core/address/lib/address/web/show_live.ex", "save_location"},
    {"apps/core/address/lib/address/web/show_live.ex", "save_provenance"},
    {"apps/core/company/lib/company/web/create_live.ex", "save"},
    {"apps/core/company/lib/company/web/platform_operator_setup_live.ex", "create"},
    {"apps/core/company/lib/company/web/platform_operator_setup_live.ex", "designate"},
    {"apps/core/company/lib/company/web/show_live.ex", "update_metadata_input"},
    {"apps/core/company/lib/company/web/show_live.ex", "update_new_activity"},
    {"apps/core/employee/lib/employee/web/form_live.ex", "save"},
    {"apps/core/employee/lib/employee/web/index_live.ex", "delete"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "add_subordinate"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "attach_address"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "delete"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "detach_address"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "remove_subordinate"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "save_address_kinds"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "save_address_priority"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "save_department"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "save_employee_type"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "save_field"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "save_status"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "save_supervisor"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "save_user"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "toggle_add_subordinate"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "toggle_address_primary"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "toggle_edit_kind"},
    {"apps/core/employee/lib/employee/web/type_form_live.ex", "save"},
    {"apps/core/employee/lib/employee/web/type_index_live.ex", "delete"},
    {"apps/core/geonames/lib/geonames/web/admin1_live.ex", "save-admin1-name"},
    {"apps/core/geonames/lib/geonames/web/countries_live.ex", "save-country-name"},
    {"apps/core/geonames/lib/geonames/web/countries_live.ex", "update-countries"},
    {"apps/core/user/lib/user/web/appearance_live.ex", "save"},
    {"apps/core/user/lib/user/web/database_queries_live/index.ex", "delete"},
    {"apps/core/user/lib/user/web/database_queries_live/index.ex", "duplicate"},
    {"apps/core/user/lib/user/web/database_queries_live/show.ex", "delete"},
    {"apps/core/user/lib/user/web/database_queries_live/show.ex", "duplicate"},
    {"apps/core/user/lib/user/web/database_queries_live/show.ex", "run_query"},
    {"apps/core/user/lib/user/web/database_queries_live/show.ex", "save"},
    {"apps/core/user/lib/user/web/form_live.ex", "save"},
    {"apps/core/user/lib/user/web/notification_bell_component.ex", "mark_all_read"},
    {"apps/core/user/lib/user/web/notification_bell_component.ex", "toggle_dropdown"},
    {"apps/core/user/lib/user/web/notifications_live.ex", "mark_all_read"},
    {"apps/core/user/lib/user/web/notifications_live.ex", "mark_read"},
    {"apps/core/user/lib/user/web/password_live.ex", "save"},
    {"apps/core/user/lib/user/web/profile_live.ex", "save"},
    {"apps/core/user/lib/user/web/show_live.ex", "add_selected_capabilities"},
    {"apps/core/user/lib/user/web/show_live.ex", "assign_selected_roles"},
    {"apps/core/user/lib/user/web/show_live.ex", "delete"},
    {"apps/core/user/lib/user/web/show_live.ex", "deny_capability"},
    {"apps/core/user/lib/user/web/show_live.ex", "link_employee"},
    {"apps/core/user/lib/user/web/show_live.ex", "remove_capability"},
    {"apps/core/user/lib/user/web/show_live.ex", "remove_role"},
    {"apps/core/user/lib/user/web/show_live.ex", "save_company"},
    {"apps/core/user/lib/user/web/show_live.ex", "save_field"},
    {"apps/core/user/lib/user/web/show_live.ex", "save_new_employee"},
    {"apps/core/user/lib/user/web/show_live.ex", "toggle_assign_roles"},
    {"apps/core/user/lib/user/web/show_live.ex", "toggle_change_password"},
    {"apps/core/user/lib/user/web/show_live.ex", "toggle_effective_permissions"},
    {"apps/core/user/lib/user/web/show_live.ex", "toggle_link_employee"},
    {"apps/core/user/lib/user/web/show_live.ex", "unlink_employee"},
    {"apps/core/user/lib/user/web/show_live.ex", "update_password"},
    {"apps/core/user_administration/lib/user_administration/web/index_live.ex", "delete"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "add-widget"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "move-down"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "move-up"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "remove-widget"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "reorder-widgets"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "toggle-layout-edit"}
  ]

  test "every write-shaped handle_event is capability-guarded or explicitly opted out" do
    offenders =
      @workspace_root
      |> scanned_files()
      |> Enum.flat_map(&offenders/1)
      |> Enum.sort()
      |> Enum.uniq()

    new = for entry <- offenders, entry not in @tracked, do: entry
    fixed = for entry <- @tracked, entry not in offenders, do: entry

    assert new == [],
           """
           These write-shaped handle_event/3 clauses are not covered by any
           deny clause and not opted out:

           #{format_entries(new)}

           A hidden control is not a guard (#376). Either refuse the event when
           the actor lacks the capability:

               def handle_event(event, _params, %{assigns: %{can_update?: false}} = socket)
                   when event in @write_events,
                 do: write_forbidden(socket)

           or, if the name is write-shaped only (sort/filter/UI state) or the
           route already mounts under the write capability, list it under
           @write_guard_opt_out with a reason comment.
           """

    assert fixed == [],
           """
           These are listed as tracked debt but no longer offend — the module
           gained a guard or opt-out:

           #{format_entries(fixed)}

           Delete them from @tracked. An exemption that outlives its defect is
           how the next real one gets waved through.
           """
  end

  ## Scanning

  defp scanned_files(root) do
    ["apps/*/*/lib/**/web/**/*.ex", "apps/web/lib/**/*.ex"]
    |> Enum.flat_map(&Path.wildcard(Path.join(root, &1)))
    |> Enum.uniq()
    |> Enum.flat_map(fn path ->
      with {:ok, source} <- File.read(path),
           {:ok, ast} <- Code.string_to_quoted(source),
           true <- defines_handle_event?(ast) do
        [{Path.relative_to(path, root), ast}]
      else
        _ -> []
      end
    end)
  end

  defp defines_handle_event?(ast) do
    {_, found?} =
      Macro.prewalk(ast, false, fn
        {:def, _, [{:handle_event, _, _} | _]} = node, _found ->
          {node, true}

        node, found ->
          {node, found}
      end)

    found?
  end

  defp offenders({path, ast}) do
    attributes = literal_attributes(ast)

    clauses = handle_event_clauses(ast, attributes)

    covered =
      clauses |> Enum.filter(& &1.deny?) |> Enum.flat_map(& &1.covered_events)

    opt_out = Map.get(attributes, @opt_out_attribute, [])

    clauses
    |> Enum.flat_map(& &1.event_names)
    |> Enum.uniq()
    |> Enum.map(&{path, &1})
    |> Enum.filter(fn {_path, event} ->
      write_shaped?(event) and event not in covered and event not in opt_out
    end)
  end

  # Returns clause facts: the literal event names it handles, whether it is a
  # deny clause, and which events that deny clause covers.
  defp handle_event_clauses(ast, attributes) do
    {_, clauses} =
      Macro.prewalk(ast, [], fn
        {:def, _, [head, _body]} = node, acc ->
          case handle_event_head(head, attributes) do
            nil -> {node, acc}
            facts -> {node, [facts | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    clauses
  end

  # def handle_event(name, params, socket_pattern) [when guard]
  defp handle_event_head(
         {:when, _, [{:handle_event, _, [event, _params, socket]}, guard]},
         attributes
       ) do
    clause_facts(event, socket, guard, attributes)
  end

  defp handle_event_head({:handle_event, _, [event, _params, socket]}, attributes) do
    clause_facts(event, socket, nil, attributes)
  end

  defp handle_event_head(_head, _attributes), do: nil

  defp clause_facts(event, socket_pattern, guard, attributes) do
    deny? = deny_pattern?(socket_pattern)

    %{
      event_names: if(is_binary(event), do: [event], else: []),
      deny?: deny?,
      covered_events: if(deny?, do: covered_events(event, guard, attributes), else: [])
    }
  end

  # A deny clause refuses the event when the actor lacks a capability assign:
  # the socket pattern matches %{assigns: %{can_*?: false}}.
  defp deny_pattern?(socket_pattern) do
    {_, deny?} =
      Macro.prewalk(socket_pattern, false, fn
        {assign, false} = node, deny? when is_atom(assign) ->
          name = Atom.to_string(assign)
          {node, deny? or (String.starts_with?(name, "can_") and String.ends_with?(name, "?"))}

        node, deny? ->
          {node, deny?}
      end)

    deny?
  end

  # Which events a deny clause covers: the literal event name in its head, or
  # `when event in @attr` (resolved against the module's literal attributes)
  # or an inline literal list.
  defp covered_events(event, _guard, _attributes) when is_binary(event), do: [event]

  defp covered_events(_event, nil, _attributes), do: []

  defp covered_events(_event, guard, attributes) do
    {_, covered} =
      Macro.prewalk(guard, [], fn
        {:in, _, [_, {:@, _, [{attribute, _, nil}]}]} = node, acc ->
          {node, acc ++ Map.get(attributes, attribute, [])}

        {:in, _, [_, list]} = node, acc when is_list(list) ->
          if Enum.all?(list, &is_binary/1),
            do: {node, acc ++ list},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    covered
  end

  # Module attributes whose value is a literal ~w sigil or list of strings.
  defp literal_attributes(ast) do
    {_, attributes} =
      Macro.prewalk(ast, %{}, fn
        {:@, _, [{name, _, [value]}]} = node, acc ->
          case literal_strings(value) do
            nil -> {node, acc}
            strings -> {node, Map.put(acc, name, strings)}
          end

        node, acc ->
          {node, acc}
      end)

    attributes
  end

  # ~w(a b c) or a list whose elements are all string literals.
  defp literal_strings({:sigil_w, _, [{:<<>>, _, [string]}, _]}), do: String.split(string)
  defp literal_strings({:sigil_W, _, [{:<<>>, _, [string]}, _]}), do: String.split(string)

  defp literal_strings(list) when is_list(list) do
    if Enum.all?(list, &is_binary/1), do: list
  end

  defp literal_strings(_), do: nil

  defp write_shaped?(event) do
    # Hyphens and underscores both separate words: `add-widget` is the same
    # shape as `add_widget`, and treating them differently would make a
    # hyphen the way to escape this test.
    normalized = String.replace(event, "-", "_")

    normalized in @exact_writes or
      Enum.any?(@write_verbs, &String.starts_with?(normalized, &1 <> "_"))
  end

  defp format_entries(entries) do
    Enum.map_join(entries, "\n", fn {path, event} -> "    #{path}  #{event}" end)
  end
end
