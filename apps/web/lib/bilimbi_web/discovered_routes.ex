defmodule BilimbiWeb.DiscoveredRoutes do
  @moduledoc false

  @manifest_path Path.expand(
                   "../../../../_build/#{Application.compile_env!(:web, :mix_env)}/bilimbi_routes.exs",
                   __DIR__
                 )

  def module_routes(routes) when is_list(routes) do
    Enum.reject(routes, &(&1[:source] == "web"))
  end

  defmacro inject do
    manifest_path = @manifest_path

    routes =
      if File.regular?(manifest_path) do
        {list, _} = Code.eval_file(manifest_path)
        module_routes(list)
      else
        []
      end

    quotes =
      for route <- routes, live_module?(route) do
        path = route.path
        live_mod = route.live
        session = Map.get(route, :session, :auth)
        capability = Map.get(route, :capability)
        session_name = :"discovered_#{:erlang.phash2({path, live_mod})}"
        {pipeline, hooks} = pipes_and_hooks(session, capability)

        quote do
          scope "/" do
            pipe_through unquote(pipeline)

            live_session unquote(session_name), on_mount: unquote(hooks) do
              live unquote(path), unquote(live_mod)
            end
          end
        end
      end

    quote do
      (unquote_splicing(quotes))
    end
  end

  defp live_module?(route) do
    case Map.get(route, :live) do
      live when is_atom(live) and not is_nil(live) -> true
      _other -> false
    end
  end

  defp pipes_and_hooks(:anonymous, _cap) do
    {[:browser, :redirect_if_authenticated], [{BilimbiWeb.UserAuth, :redirect_if_authenticated}]}
  end

  defp pipes_and_hooks(:auth, nil) do
    {[:browser, :require_authenticated], [{BilimbiWeb.UserAuth, :require_authenticated}]}
  end

  defp pipes_and_hooks(:auth, cap) when is_binary(cap) do
    {[:browser, :require_authenticated],
     [
       {BilimbiWeb.UserAuth, :require_authenticated},
       {BilimbiWeb.UserAuth, {:require_capability, cap}}
     ]}
  end

  defp pipes_and_hooks(:none, _cap) do
    {[:browser], []}
  end
end
