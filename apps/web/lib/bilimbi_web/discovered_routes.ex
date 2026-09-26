defmodule BilimbiWeb.DiscoveredRoutes do
  @moduledoc false

  @manifest_path Path.expand(
                   "../../../../_build/#{Application.compile_env!(:web, :mix_env)}/bilimbi_routes.exs",
                   __DIR__
                 )

  def module_routes(routes) when is_list(routes) do
    Enum.reject(routes, &(&1[:source] == "web" or not Map.has_key?(&1, :path)))
  end

  defmacro inject do
    routes =
      if File.regular?(@manifest_path) do
        {list, _} = Code.eval_file(@manifest_path)
        module_routes(list)
      else
        []
      end

    routes = [
      %{
        path: "/dashboard",
        live: BilimbiWeb.DashboardLive,
        session: :auth,
        source: "web",
        layer: :web
      }
      | routes
    ]

    groups =
      routes
      |> Enum.filter(&(is_atom(&1[:live]) and not is_nil(&1[:live])))
      |> Enum.group_by(&session_group/1)
      |> Enum.sort_by(&elem(&1, 0))

    blocks =
      for {group, routes} <- groups do
        {name, pipeline, hooks} = session_options(group)

        # These atoms come exclusively from trusted, compiled route declarations.
        # The action identifies the destination before its mount can read data.
        policies = Map.new(routes, &{:"bilimbi:#{&1.path}", &1[:capability]})
        hooks = hooks ++ [{BilimbiWeb.RouteAccess, policies}]

        declarations =
          for route <- routes do
            action = :"bilimbi:#{route.path}"

            quote do
              live unquote(route.path), unquote(route.live), unquote(action),
                metadata: %{bilimbi_route_owner: unquote({route.layer, route.source})}
            end
          end

        quote do
          scope "/" do
            pipe_through unquote(pipeline)

            live_session unquote(name), on_mount: unquote(Macro.escape(hooks)) do
              (unquote_splicing(declarations))
            end
          end
        end
      end

    controller_blocks =
      for route <- routes, is_atom(route[:controller]) and not is_nil(route[:controller]) do
        controller_block(route)
      end

    quote do
      (unquote_splicing(blocks ++ controller_blocks))
    end
  end

  defp controller_block(%{operator: true} = route) do
    raise ArgumentError,
          "controller route #{route.path} cannot be operator-only; no plug enforces that boundary"
  end

  defp controller_block(route) do
    {_name, pipeline, _hooks} = session_options(Map.get(route, :session, :auth))
    verb = Map.get(route, :verb, :get)

    case route[:capability] do
      nil ->
        quote do
          scope "/" do
            pipe_through unquote(pipeline)

            match unquote(verb),
                  unquote(route.path),
                  unquote(route.controller),
                  unquote(route.action),
                  metadata: %{bilimbi_route_owner: unquote({route.layer, route.source})}
          end
        end

      capability ->
        name = :"bilimbi_capability:#{verb}:#{route.path}"

        quote do
          pipeline unquote(name) do
            plug :require_capability, unquote(capability)
          end

          scope "/" do
            pipe_through unquote(pipeline ++ [name])

            match unquote(verb),
                  unquote(route.path),
                  unquote(route.controller),
                  unquote(route.action),
                  metadata: %{bilimbi_route_owner: unquote({route.layer, route.source})}
          end
        end
    end
  end

  defp session_group(%{session: :auth, operator: true}), do: :operator
  defp session_group(route), do: Map.get(route, :session, :auth)

  defp session_options(:auth) do
    {:authenticated, [:browser, :require_authenticated],
     [{BilimbiWeb.UserAuth, :require_authenticated}]}
  end

  defp session_options(:operator) do
    {:operator, [:browser, :require_authenticated],
     [
       {BilimbiWeb.UserAuth, :require_authenticated},
       {BilimbiWeb.UserAuth, :require_platform_operator}
     ]}
  end

  defp session_options(:anonymous) do
    {:discovered_anonymous, [:browser, :redirect_if_authenticated],
     [{BilimbiWeb.UserAuth, :redirect_if_authenticated}]}
  end

  defp session_options(:none), do: {:discovered_public, [:browser], []}
end
