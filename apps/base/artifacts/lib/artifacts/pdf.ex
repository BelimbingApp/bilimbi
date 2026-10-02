defmodule Bilimbi.Base.Artifacts.PDF do
  @moduledoc """
  PDF generation contract, implemented by the owning adapter when needed.

  Base authorizes before rendering and stores the result through the same
  private upload path. The owner controls templates, document data and its PDF
  engine. Use `Bilimbi.Base.Artifacts.PDF.Renderer.render/1` for simple text
  and table documents rather than maintaining a domain-local PDF serializer.
  The result must be a complete PDF binary; no shell command, URL,
  browser session or HTML engine is selected by Base. Renderers must not fetch
  untrusted remote resources or log document contents.
  """
  alias Bilimbi.Base.Artifacts.Owner
  alias Bilimbi.Base.Tenancy.Scope

  @callback render_pdf(Scope.t(), pos_integer(), Owner.document_ref(), map()) ::
              {:ok, binary()} | {:error, term()}
end
