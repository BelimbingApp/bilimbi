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

  A `shell.*` key is a panel the shared shell itself renders, on every
  authenticated page (`Bilimbi.Base.UI.Layouts.app/1`). The shell passes
  `optional`, because a composition without the provider has nothing to
  apologise for in the top bar, and takes the component id from `shell_id/1`
  so the provider can address its own panel with `send_update/2` from an
  `on_mount` hook without either side hard-coding the other's id.
  """

  use Phoenix.Component

  @doc """
  The component id the shell gives the panel it renders for a `shell.*` key.

  The provider's `on_mount` hook passes the same id to `send_update/2`.
  """
  @spec shell_id(String.t()) :: String.t()
  def shell_id("shell." <> name) when name != "", do: "app-shell-" <> name

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

    attr(:optional, :boolean,
      default: false,
      doc: "render nothing, not the not-installed notice, when no loaded module provides the key"
    )

    def discovered_panel(%{optional: true} = assigns), do: ~H""

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

    attr(:optional, :boolean,
      default: false,
      doc: "render nothing, not the not-installed notice, when no loaded module provides the key"
    )

    def discovered_panel(assigns) do
      case resolve(assigns.key) do
        {:ok, %{capability: capability} = panel} ->
          if loaded?(panel, assigns.optional) and
               (is_nil(capability) or Bilimbi.Base.UI.allowed?(assigns.current_scope, capability)) do
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

        :error when assigns.optional ->
          ~H""

        :error ->
          ~H"""
          <div id={@id} class="rounded-xl border border-line bg-surface-muted p-4 text-sm text-muted">
            This panel is provided by a module that is not installed ({@key}).
          </div>
          """
      end
    end

    # The manifest is the workspace's, while a package's own test VM loads
    # only its dependency closure. An optional panel whose provider is not
    # loaded here is absent, the same as one nobody declared.
    defp loaded?(_panel, false), do: true
    defp loaded?(%{live_component: module}, true), do: Code.ensure_loaded?(module)
  end
end
