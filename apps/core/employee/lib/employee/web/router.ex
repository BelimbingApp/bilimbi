defmodule Bilimbi.Core.Employee.Web.Router do
  @moduledoc false

  @routes_file Path.expand("../../../priv/web_routes.exs", __DIR__)
  @external_resource @routes_file
  @routes elem(Code.eval_file(@routes_file), 0)

  @spec routes() :: [map()]
  def routes, do: @routes
end
