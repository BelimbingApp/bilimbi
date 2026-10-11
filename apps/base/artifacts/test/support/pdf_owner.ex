defmodule Bilimbi.Base.Artifacts.TestPDFOwner do
  @moduledoc false
  @behaviour Bilimbi.Base.Artifacts.Owner
  @behaviour Bilimbi.Base.Artifacts.PDF
  alias Bilimbi.Base.Artifacts.PDF.Renderer

  @impl true
  def artifact_owner_id, do: "test/pdf"
  @impl true
  def authorize(scope, company, operation, ref),
    do: Bilimbi.Base.Artifacts.TestOwner.authorize(scope, company, operation, ref)

  @impl true
  def render_pdf(_scope, _company, _ref, data), do: Renderer.render(data)
  @impl true
  def render_html(scope, _company, _ref, data) do
    if Process.get(:raise_pdf_html), do: raise(inspect(data))
    send(self(), {:pdf_context, Bilimbi.Base.Audit.Context.get()})
    send(self(), {:pdf_platform_operator, Bilimbi.Base.Tenancy.Scope.platform_operator?(scope)})
    send(self(), {:html_rendered, Bilimbi.Base.Tenancy.Scope.actor(scope)})
    {:ok, Map.fetch!(data, :html)}
  end

  @impl true
  def pdf_request(_scope, _company, _ref, request) do
    send(self(), {:pdf_request, request})

    {:ok,
     %{
       mode: :document,
       data: %{title: "Queued", blocks: [{:text, "facts"}]},
       options: Process.get(:pdf_options, []),
       metadata: %{routing_id: "record-1"}
     }}
  end

  @impl true
  def pdf_rendered(_scope, _company, _ref, event) do
    send(self(), {:pdf_rendered, event})
    Process.get(:pdf_listener_result, :ok)
  end
end
