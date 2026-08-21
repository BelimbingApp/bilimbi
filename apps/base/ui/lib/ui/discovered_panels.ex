defmodule Bilimbi.Base.UI.DiscoveredPanels do
  @moduledoc """
  Renders module-contributed embeddable panels by workspace-unique string key.

  A module declares an embed entry in its `priv/web_routes.exs`
  (`%{embed: "employee.accounts", live_component: ..., capability: ...}`);
  discovery validates it fail-closed and writes it into the same compile-time
  manifest `RouteContract` reads. A page renders the panel with
  `<.discovered_panel key="employee.accounts" ...>` and never names the
  providing module, so a capability can live where its writes live without a
  reverse descriptor edge (#570; ADR 0006 second amendment).

  Resolution is honest in both failure directions: a key nobody provides
  renders a visible not-installed notice rather than nothing, while a declared
  capability the current scope lacks hides the panel the way menu entries hide.
  The panel component itself still re-authorizes every write it handles;
  mount-time visibility is presentation state, not an authorization decision.
  """

  use Phoenix.Component

  @manifest_path Path.join([
                   Path.expand("../../../../..", __DIR__),
                   "_build",
                   "#{Application.compile_env!(:bilimbi_base_ui, :mix_env)}",
                   "bilimbi_routes.exs"
                 ])
  @external_resource @manifest_path
  @panels (if File.regular?(@manifest_path) do
             @manifest_path
             |> Code.eval_file()
             |> elem(0)
             |> Enum.filter(&Map.has_key?(&1, :embed))
             |> Map.new(&{&1.embed, &1})
           else
             %{}
           end)

  @doc "Resolves an embed key to its manifest entry."
  @spec resolve(String.t()) :: {:ok, map()} | :error
  # Compile-time branch: a standalone Base UI build has no manifest and no
  # panels, and the type checker rightly flags a Map.fetch on the empty
  # literal as constantly :error. The workspace build takes the real clause.
  if @panels == %{} do
    def resolve(key) when is_binary(key), do: :error
  else
    def resolve(key) when is_binary(key), do: Map.fetch(@panels, key)
  end

  attr :key, :string, required: true
  attr :id, :string, required: true
  attr :current_scope, :map, required: true
  attr :opts, :map, default: %{}, doc: "assigns passed through to the panel component"

  def discovered_panel(assigns) do
    case resolve(assigns.key) do
      {:ok, %{capability: capability} = panel} ->
        if is_nil(capability) or Bilimbi.Base.UI.allowed?(assigns.current_scope, capability) do
          assigns = assign(assigns, :panel, panel)

          ~H"""
          <.live_component
            module={@panel.live_component}
            id={@id}
            current_scope={@current_scope}
            {@opts}
          />
          """
        else
          ~H""
        end

      :error ->
        ~H"""
        <div id={@id} class="rounded-xl border border-line bg-surface-muted p-4 text-sm text-muted">
          This panel is provided by a module that is not installed ({@key}).
        </div>
        """
    end
  end
end
