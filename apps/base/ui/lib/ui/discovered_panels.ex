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

  # Compile-time branch: a build whose manifest declares no embeds — every
  # standalone Base UI build, and the workspace until the first provider lands
  # — has a constantly-empty panel table, and the type checker rightly rejects
  # code pretending otherwise. Each world compiles only its own truth.
  if @panels == %{} do
    @doc "Resolves an embed key to its manifest entry."
    @spec resolve(String.t()) :: {:ok, map()} | :error
    def resolve(key) when is_binary(key), do: :error

    @doc "Runs a panel operation declared for an installed panel."
    @spec dispatch(String.t(), atom(), [term()]) :: {:error, :not_installed}
    def dispatch(_key, _operation, _args), do: {:error, :not_installed}

    attr(:key, :string, required: true)
    attr(:id, :string, required: true)
    attr(:current_scope, :map, required: true)
    attr(:opts, :map, default: %{}, doc: "assigns passed through to the panel component")

    def discovered_panel(assigns) do
      ~H"""
      <div id={@id} class="rounded-xl border border-line bg-surface-muted p-4 text-sm text-muted">
        This panel is provided by a module that is not installed ({@key}).
      </div>
      """
    end
  else
    @doc "Resolves an embed key to its manifest entry."
    @spec resolve(String.t()) :: {:ok, map()} | :error
    def resolve(key) when is_binary(key), do: Map.fetch(@panels, key)

    @doc "Runs an operation through the panel's declared handler."
    @spec dispatch(String.t(), atom(), [term()]) :: term()
    def dispatch(key, operation, args)
        when is_binary(key) and is_atom(operation) and is_list(args) do
      case resolve(key) do
        {:ok, %{operation_handler: nil}} ->
          {:error, :operation_not_supported}

        {:ok, %{operation_handler: handler}} ->
          apply(handler, :dispatch, [operation | args])

        :error ->
          {:error, :not_installed}
      end
    end

    attr(:key, :string, required: true)
    attr(:id, :string, required: true)
    attr(:current_scope, :map, required: true)
    attr(:opts, :map, default: %{}, doc: "assigns passed through to the panel component")

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
end
