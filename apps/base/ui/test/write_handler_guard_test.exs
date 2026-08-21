defmodule Bilimbi.Base.UI.WriteHandlerGuardTest do
  @moduledoc """
  A write-shaped `handle_event/3` must be refused when the actor lacks the
  write capability. Hiding the button in the template is not a guard: #376
  found ten write handlers on the company show page reachable by any actor
  holding only `admin.company.view`, because `{@can_update?}` hid the controls
  and nothing else refused the event.

  ## What counts as covered

  All three guard idioms in production use, each mechanically detected:

      # 1. deny clause — refusal in the socket pattern
      def handle_event("delete", _params, %{assigns: %{can_delete?: false}} = socket),
        do: write_forbidden(socket)

      @write_events ~w(save_details unlink_address ...)
      def handle_event(event, _params, %{assigns: %{can_update?: false}} = socket)
          when event in @write_events,
          do: write_forbidden(socket)

      # 2. inline branch on a can_*? assign in the clause body
      def handle_event("save_department", params, socket) do
        if socket.assigns.can_manage? do ... else {:noreply, flash_forbidden} end
      end

      # 3. capability check in the clause body
      def handle_event("delete", params, socket) do
        cond do
          not allowed?(socket.assigns.current_scope, "admin.user.delete") -> ...
      end

      # 4. a local predicate rather than an assign access (base/session)
      def handle_event("terminate", %{"id" => id}, socket) do
        if can_manage?(socket) do ... else {:noreply, flash_forbidden} end
      end

  Idioms 2, 3 and 4 check that a guard is *present*, not that it is correct
  — the same approximation idiom 1 makes. All four are guards; the deny clause
  is a house style, not a security property, and a test that enforced one
  style while claiming to enforce authorization would be argued with and then
  ignored (review of #415).

  Plus **route gating, read from the data that declares it**: each module
  ships `priv/web_routes.exs` mapping a LiveView to the capability its route
  requires. A LiveView every one of whose routes mounts under a
  write-suffixed capability (`create`, `update`, `delete`, `manage`, `write`,
  `import`, `restore`, `terminate`, `designate`) is covered — there is no
  weaker capability to refuse. A read capability (`list`, `view`) covers
  nothing.

  ## The opt-out

      # Sort reorders the reading of the list; it writes nothing.
      @write_guard_opt_out ~w(sort_subordinates)

  `@write_guard_opt_out` is for events that are write-shaped **by name only**
  — sort/filter/UI-state toggles — and for self-service actions on the
  actor's own account, where no admin capability applies. Every entry needs a
  reason comment next to the attribute; a lie here is greppable and review's
  job, not the test's.

  ## Derived, not a fixture

  The file set is discovered by content (`handle_event/3` definitions under
  `web/` trees and `apps/web`), the event names come from the parsed AST, and
  coverage comes from the module's own clauses, attributes, and route
  declarations. Nothing here mirrors a hand-written list of modules —
  `workspace_boundary_test.exs` is the cautionary case: it mirrored what it
  checked, caught nothing, and serialised every new module through one file.

  `@tracked` is acknowledged debt, not endorsement: each entry is an
  unguarded write-shaped event that existed when this test landed. Fixing a
  module — guard, route, or opt-out — **fails the test until its entry is
  deleted**, which is what keeps the list from becoming wallpaper. That
  mechanism already forced the truth once: the first cut of this test
  recognised only the deny clause, counted 76 "unguarded" events, and review
  walked every clause body to find 38 of them guarded inline (#415). The
  remaining list is short enough to read, which is the whole point.

  ## What this does not check

  Whether an inline guard is *right* — right capability, right branch — is
  review's question. `validate`/`change` form-input events are not
  write-shaped and are not checked. The assign name must start with `can_`
  and end with `?`; a differently named deny assign fails this test and either
  gets renamed or the convention grows deliberately.
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

  # A route capability whose final segment is one of these authorizes writes:
  # mounting under it is coverage. Everything else (list, view, read) is a
  # read capability and covers nothing.
  @write_capability_suffixes ~w(create update delete manage write import restore terminate designate)

  @opt_out_attribute :write_guard_opt_out

  # Acknowledged debt from when this test landed. Each {module_path, event}
  # is an unguarded write-shaped handler. Delete the entry in the same change
  # that guards or opts out the event.
  @tracked [
    {"apps/core/company/lib/company/web/show_live.ex", "update_metadata_input"},
    {"apps/core/company/lib/company/web/show_live.ex", "update_new_activity"},
    {"apps/core/employee/lib/employee/web/show_live.ex", "toggle_add_subordinate"},
    {"apps/core/user/lib/user/web/appearance_live.ex", "save"},
    {"apps/core/user/lib/user/web/notification_bell_component.ex", "mark_all_read"},
    {"apps/core/user/lib/user/web/notification_bell_component.ex", "toggle_dropdown"},
    {"apps/core/user/lib/user/web/notifications_live.ex", "mark_all_read"},
    {"apps/core/user/lib/user/web/notifications_live.ex", "mark_read"},
    {"apps/core/user/lib/user/web/password_live.ex", "save"},
    {"apps/core/user/lib/user/web/profile_live.ex", "save"},
    {"apps/core/user/lib/user/web/show_live.ex", "toggle_assign_roles"},
    {"apps/core/user/lib/user/web/show_live.ex", "toggle_change_password"},
    {"apps/core/user/lib/user/web/show_live.ex", "toggle_effective_permissions"},
    {"apps/core/user/lib/user/web/show_live.ex", "toggle_link_employee"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "add-widget"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "move-down"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "move-up"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "remove-widget"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "reorder-widgets"},
    {"apps/web/lib/bilimbi_web/live/dashboard_live.ex", "toggle-layout-edit"}
  ]

  test "every write-shaped handle_event is capability-guarded or explicitly opted out" do
    route_write_modules = route_write_modules()

    offenders =
      @workspace_root
      |> scanned_files()
      |> Enum.flat_map(&offenders(&1, route_write_modules))
      |> Enum.sort()
      |> Enum.uniq()

    new = for entry <- offenders, entry not in @tracked, do: entry
    fixed = for entry <- @tracked, entry not in offenders, do: entry

    assert new == [],
           """
           These write-shaped handle_event/3 clauses have no guard (deny
           clause, inline can_*? branch, allowed?/2 check, or a route mounted
           under a write capability) and no opt-out:

           #{format_entries(new)}

           A hidden control is not a guard (#376). Refuse the event when the
           actor lacks the capability, or — if the name is write-shaped only,
           or the action is self-service on the actor's own account, or the
           route already mounts under the write capability — list it under
           @write_guard_opt_out with a reason comment.
           """

    assert fixed == [],
           """
           These are listed as tracked debt but no longer offend — the module
           gained a guard, a gating route, or an opt-out:

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

  defp offenders({path, ast}, route_write_modules) do
    attributes = literal_attributes(ast)

    route_covered? =
      case module_name(ast) do
        nil -> false
        name -> Map.get(route_write_modules, name, false)
      end

    clauses = handle_event_clauses(ast, attributes)

    covered =
      clauses
      |> Enum.filter(& &1.guarded?)
      |> Enum.flat_map(& &1.covered_events)

    opt_out = Map.get(attributes, @opt_out_attribute, [])

    clauses
    |> Enum.flat_map(& &1.event_names)
    |> Enum.uniq()
    |> Enum.map(&{path, &1})
    |> Enum.filter(fn {_path, event} ->
      write_shaped?(event) and event not in covered and event not in opt_out and
        not route_covered?
    end)
  end

  # Returns clause facts: the literal event names it handles, whether it is
  # guarded, and which events that guard covers.
  defp handle_event_clauses(ast, attributes) do
    {_, clauses} =
      Macro.prewalk(ast, [], fn
        {:def, _, [head, [do: body]]} = node, acc ->
          case handle_event_head(head, attributes, body) do
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
         attributes,
         body
       ) do
    clause_facts(event, socket, guard, attributes, body)
  end

  defp handle_event_head({:handle_event, _, [event, _params, socket]}, attributes, body) do
    clause_facts(event, socket, nil, attributes, body)
  end

  defp handle_event_head(_head, _attributes, _body), do: nil

  defp clause_facts(event, socket_pattern, guard, attributes, body) do
    deny? = deny_pattern?(socket_pattern)
    guarded? = deny? or body_guarded?(body)

    %{
      event_names: if(is_binary(event), do: [event], else: []),
      guarded?: guarded?,
      covered_events:
        if deny? do
          covered_events(event, guard, attributes)
        else
          if(is_binary(event), do: [event], else: [])
        end
    }
  end

  # Idiom 1: the socket pattern matches %{assigns: %{can_*?: false}}.
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

  # Idioms 2, 3 and 4: the clause body branches on a can_*? assign read through
  # `.assigns` (`socket.assigns.can_manage?`), calls allowed?/2 in any form, or
  # calls a local can_*? predicate (`can_manage?(socket)`).
  defp body_guarded?(body) do
    {_, guarded?} =
      Macro.prewalk(body, false, fn
        # socket.assigns.can_manage? — the .assigns access is itself a call
        # node inside the outer field access.
        {{:., _, [{{:., _, [_, :assigns]}, _, _}, assign]}, _, _} = node, guarded?
        when is_atom(assign) ->
          name = Atom.to_string(assign)

          {node, guarded? or (String.starts_with?(name, "can_") and String.ends_with?(name, "?"))}

        # allowed?(...) or Some.Alias.allowed?(...)
        {:allowed?, _, _} = node, _guarded? ->
          {node, true}

        # Idiom 4: a local predicate — `if can_manage?(socket)`. There is no
        # `.assigns` access to anchor on, so the function name is the only
        # signal. `is_list(args)` is what separates a call from a variable of
        # the same name, whose third element is the context atom.
        #
        # This clause must stay below the allowed?/2 one: allowed? does not
        # start with `can_`, so matching it here first would drop idiom 3.
        {name, _, args} = node, guarded? when is_atom(name) and is_list(args) ->
          local = Atom.to_string(name)

          {node,
           guarded? or (String.starts_with?(local, "can_") and String.ends_with?(local, "?"))}

        node, guarded? ->
          {node, guarded?}
      end)

    guarded?
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

  # The module name of a scanned file: its first defmodule, as a string.
  defp module_name(ast) do
    {_, name} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, _, [{:__aliases__, _, parts}, _]} = node, nil ->
          {node, Enum.map_join(parts, ".", &to_string/1)}

        node, name ->
          {node, name}
      end)

    name
  end

  # LiveViews every one of whose routes mounts under a write-suffixed
  # capability. Read from `priv/web_routes.exs` — the data that actually
  # gates the route — not from a hand-written list.
  defp route_write_modules do
    route_modules =
      @workspace_root
      |> Path.join("apps/*/*/priv/web_routes.exs")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        with {:ok, source} <- File.read(path),
             {:ok, ast} <- Code.string_to_quoted(source) do
          route_entries(ast)
        else
          _ -> []
        end
      end)
      |> Enum.group_by(fn {module, _capability} -> module end, fn {_module, capability} ->
        capability
      end)

    for {module, capabilities} <- route_modules,
        Enum.all?(capabilities, &write_capability?/1),
        into: %{},
        do: {module, true}
  end

  # [{module_name, capability}] from the list-of-maps route manifest. Each
  # map carries one :live and one :capability among other keys, so pair each
  # capability with the nearest preceding :live rather than assuming order.
  # Keyword pairs in a map AST are plain {key, value} tuples.
  defp route_entries(ast) do
    {_, entries} =
      Macro.prewalk(ast, [], fn
        {key, value} = node, acc when key in [:live, :capability] ->
          case route_value(value) do
            nil -> {node, acc}
            parsed -> {node, [{key, parsed} | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    {_, pairs} =
      Enum.reverse(entries)
      |> Enum.reduce({nil, []}, fn
        {:live, module}, {_live, pairs} -> {module, pairs}
        {:capability, capability}, {live, pairs} -> {live, [{live, capability} | pairs]}
      end)

    Enum.reject(pairs, fn {live, _} -> is_nil(live) end)
  end

  defp route_value({:__aliases__, _, parts}), do: Enum.map_join(parts, ".", &to_string/1)

  defp route_value(value) when is_binary(value), do: value

  defp route_value(_), do: nil

  defp write_capability?(capability) do
    suffix = capability |> String.split(".") |> List.last()
    suffix in @write_capability_suffixes
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
