defmodule Bilimbi.Base.Artifacts.PDF do
  @moduledoc """
  PDF generation contract, implemented by the owning adapter when needed.

  Base authorizes before rendering and stores the result through the same
  private upload path. The owner controls templates, document data and its PDF
  engine. Use `Bilimbi.Base.Artifacts.PDF.Renderer.render/1` for simple text
  and table documents rather than maintaining a domain-local PDF serializer.
  The result must be a complete PDF binary. For HTML templates use
  `render_inline/6` or `render_view/6`; Base runs isolated Chromium with
  external resources and scripts disabled. Templates must embed their styles,
  fonts and images. Never log document contents.

  `render_html/4` returns complete HTML selected by the trusted owner. It runs
  with the original sealed scope, including impersonation, after authorization.
  `pdf_request/4` resolves a queued request ID into current data and options;
  passwords and document data never travel in queue arguments. `pdf_rendered/4`
  receives a completion fact with routing metadata, never passwords or data.
  Queue delivery and this callback are at least once: use request_id for
  idempotency in the owning module.
  """
  alias Bilimbi.Base.Artifacts
  alias Bilimbi.Base.Artifacts.Owner
  alias Bilimbi.Base.Artifacts.PDF.{Artifact, Engine, Rendered, RenderWorker, Tokens}
  alias Bilimbi.Base.{Queue, Settings}
  alias Bilimbi.Base.Tenancy.Scope

  @callback render_pdf(Scope.t(), pos_integer(), Owner.document_ref(), map()) ::
              {:ok, binary()} | {:error, term()}
  @callback render_html(Scope.t(), pos_integer(), Owner.document_ref(), map()) ::
              {:ok, binary()} | {:error, term()}
  @callback pdf_request(Scope.t(), pos_integer(), Owner.document_ref(), String.t()) ::
              {:ok,
               %{
                 mode: :inline | :view | :document,
                 data: map(),
                 options: keyword(),
                 metadata: map()
               }}
              | {:error, term()}
  @callback pdf_rendered(Scope.t(), pos_integer(), Owner.document_ref(), Rendered.t()) ::
              :ok | {:error, term()}
  @optional_callbacks render_pdf: 4, render_html: 4, pdf_request: 4, pdf_rendered: 4

  @type options :: keyword()
  @type result :: {:ok, Artifact.t()} | {:error, term()}

  @spec render_inline(Scope.t(), pos_integer(), module(), Owner.document_ref(), map(), options()) ::
          result()
  @doc "Renders owner-selected HTML directly, authorizes and stores a private PDF."
  def render_inline(%Scope{} = scope, company, owner, ref, data, opts \\ []) do
    with :ok <- validate_options(opts),
         :ok <- Artifacts.authorize(scope, company, owner, :create, ref),
         {:ok, html} <- owner.render_html(scope, company, ref, data),
         {:ok, bytes} <- Engine.render({:html, html}) do
      persist(scope, company, owner, ref, bytes, opts)
    end
  end

  @spec render_view(Scope.t(), pos_integer(), module(), Owner.document_ref(), map(), options()) ::
          result()
  @doc "Renders through the single-use HTTP endpoint in the issuing node."
  def render_view(%Scope{} = scope, company, owner, ref, data, opts \\ []) do
    with :ok <- validate_options(opts),
         :ok <- Artifacts.authorize(scope, company, owner, :create, ref),
         {:ok, origin} <- render_origin(),
         {:ok, token} <-
           Tokens.issue(
             %{scope: scope, company: company, owner: owner, ref: ref, data: data},
             Settings.get("pdf.signed_url_ttl_seconds"),
             Settings.get("pdf.max_render_tokens")
           ) do
      try do
        with {:ok, bytes} <- Engine.render({:url, origin <> "/pdf/render/" <> token}) do
          persist(scope, company, owner, ref, bytes, opts)
        end
      after
        Tokens.revoke(token)
      end
    end
  end

  @spec persist(Scope.t(), pos_integer(), module(), Owner.document_ref(), binary(), options()) ::
          result()
  @doc "Stores complete PDF bytes through the existing authorized artifact writer."
  def persist(%Scope{} = scope, company, owner, ref, bytes, opts \\ []) do
    with :ok <- validate_options(opts),
         <<"%PDF-", _::binary>> <- bytes,
         :ok <- Artifacts.authorize(scope, company, owner, :create, ref),
         {:ok, bytes} <- protect_bytes(bytes, opts),
         {:ok, document} <- Artifacts.put(scope, company, owner, ref, bytes, "application/pdf") do
      {:ok, Artifact.new(document, scope, opts)}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_pdf}
    end
  end

  @doc "Whether the configured Node.js and qpdf executables are available."
  @spec protection_available?() :: boolean()
  def protection_available?, do: Engine.available?(:qpdf)

  @spec protect_with_password(
          Scope.t(),
          pos_integer(),
          module(),
          Artifact.t(),
          String.t(),
          String.t() | nil
        ) :: result()
  @doc "Creates an AES-256 protected copy; the authorized source stays unchanged."
  def protect_with_password(
        %Scope{} = scope,
        company,
        owner,
        %Artifact{} = source,
        password,
        owner_password \\ nil
      ) do
    with {:ok, %{bytes: bytes, metadata: metadata}} <-
           Artifacts.read(scope, company, owner, source.document.id),
         true <- metadata.content_type == "application/pdf",
         :ok <-
           Artifacts.authorize(scope, company, owner, :create, %{
             subject: metadata.subject,
             kind: metadata.kind
           }),
         {:ok, encrypted} <- Engine.protect(bytes, password, owner_password),
         {:ok, document} <-
           Artifacts.put(
             scope,
             company,
             owner,
             %{subject: metadata.subject, kind: metadata.kind},
             encrypted,
             "application/pdf"
           ) do
      {:ok,
       %{
         source
         | document: document,
           data_version: source.data_version <> " (encrypted)",
           produced_at: DateTime.utc_now()
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_pdf}
    end
  end

  @spec enqueue(Scope.t(), pos_integer(), module(), Owner.document_ref(), String.t()) ::
          {:ok, Bilimbi.Base.Queue.JobRef.t()} | {:error, term()}
  @doc "Queues only owner and subject references, under the signed-in user's actor."
  def enqueue(%Scope{} = scope, company, owner, ref, request_id) do
    with :ok <- Artifacts.authorize(scope, company, owner, :create, ref) do
      Queue.enqueue_for(scope, RenderWorker, %{
        "owner" => Atom.to_string(owner),
        "company_id" => company,
        "subject" => ref.subject,
        "kind" => ref.kind,
        "request_id" => request_id
      })
    end
  end

  defp validate_options(opts) do
    with true <- Keyword.keyword?(opts),
         true <-
           Enum.all?(
             Keyword.keys(opts),
             &(&1 in [:password, :owner_password, :template_version, :data_version])
           ),
         true <-
           Enum.all?([:template_version, :data_version], fn key ->
             value = Keyword.get(opts, key, "spike")
             is_binary(value) and byte_size(value) in 1..255
           end) do
      :ok
    else
      _ -> {:error, :invalid_pdf_options}
    end
  end

  defp protect_bytes(bytes, opts) do
    case Keyword.get(opts, :password) do
      password when password in [nil, ""] -> {:ok, bytes}
      password -> Engine.protect(bytes, password, Keyword.get(opts, :owner_password))
    end
  end

  @doc false
  def valid_origin?(origin) when is_binary(origin) do
    case URI.new(origin) do
      {:ok, uri} ->
        uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
          is_nil(uri.userinfo) and uri.path in [nil, "", "/"] and is_nil(uri.query) and
          is_nil(uri.fragment)

      _ ->
        false
    end
  end

  def valid_origin?(_), do: false

  @doc false
  def valid_origin_setting?(value), do: value == "" or valid_origin?(value)

  defp render_origin do
    origin = Settings.get("pdf.render_origin")

    if valid_origin?(origin),
      do: {:ok, String.trim_trailing(origin, "/")},
      else: {:error, :render_origin_not_configured}
  end
end
