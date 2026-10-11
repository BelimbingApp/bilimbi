defmodule Bilimbi.Base.Artifacts.PDF.RenderWorker do
  @moduledoc false
  use Bilimbi.Base.Queue.Worker, id: "base/artifacts/render-pdf", max_attempts: 3
  alias Bilimbi.Base.Artifacts
  alias Bilimbi.Base.Artifacts.PDF
  alias Bilimbi.Base.Artifacts.PDF.Rendered
  alias Bilimbi.Base.Queue.Execution
  alias Bilimbi.Base.Tenancy.Scope

  # An exact allowlist: plaintext passwords, HTML, data, actors and free-form
  # metadata cannot become Oban arguments. The trusted owner resolves them live.
  @impl true
  def validate_args(
        %{
          "owner" => owner,
          "company_id" => company,
          "subject" => subject,
          "kind" => kind,
          "request_id" => request
        } = args
      )
      when map_size(args) == 5 and is_integer(company) and company > 0 do
    if Enum.all?([owner, subject, kind, request], &(is_binary(&1) and byte_size(&1) in 1..255)) do
      with {:ok, _owner} <- resolve_owner(owner), do: {:ok, args}
    else
      {:error, :invalid_request}
    end
  end

  def validate_args(_), do: {:error, :invalid_request}

  @impl true
  def handle_job(args, %Execution{scope: %Scope{} = scope, job_id: job_id}) do
    ref = %{subject: args["subject"], kind: args["kind"]}
    company = args["company_id"]

    with {:ok, owner} <- resolve_owner(args["owner"]),
         :ok <- Artifacts.authorize(scope, company, owner, :create, ref),
         {:ok, %{mode: mode, data: data, options: opts, metadata: metadata}} <-
           owner.pdf_request(scope, company, ref, args["request_id"]),
         {:ok, artifact} <- render(mode, scope, company, owner, ref, data, opts),
         :ok <-
           owner.pdf_rendered(scope, company, ref, %Rendered{
             request_id: args["request_id"],
             job_id: job_id,
             artifact: artifact,
             metadata: metadata
           }) do
      :ok
    else
      {:error, :forbidden} -> {:cancel, :pdf_forbidden}
      {:error, :unknown_owner} -> {:cancel, :pdf_owner_unavailable}
      _ -> {:retry, :pdf_render_failed}
    end
  end

  def handle_job(_, _), do: {:cancel, :pdf_actor_unavailable}

  defp render(:inline, scope, company, owner, ref, data, opts),
    do: PDF.render_inline(scope, company, owner, ref, data, opts)

  defp render(:view, scope, company, owner, ref, data, opts),
    do: PDF.render_view(scope, company, owner, ref, data, opts)

  defp render(:document, scope, company, owner, ref, data, opts) do
    with {:ok, bytes} <- owner.render_pdf(scope, company, ref, data),
         do: PDF.persist(scope, company, owner, ref, bytes, opts)
  end

  defp render(_, _, _, _, _, _, _), do: {:error, :invalid_mode}

  defp resolve_owner(name) do
    owner = Module.safe_concat([name])

    if Code.ensure_loaded?(owner) and
         Enum.all?(
           [{:authorize, 4}, {:artifact_owner_id, 0}, {:pdf_request, 4}, {:pdf_rendered, 4}],
           fn {fun, arity} -> function_exported?(owner, fun, arity) end
         ), do: {:ok, owner}, else: {:error, :unknown_owner}
  rescue
    ArgumentError -> {:error, :unknown_owner}
  end
end
