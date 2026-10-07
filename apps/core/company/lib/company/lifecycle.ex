defmodule Bilimbi.Core.Company.Lifecycle do
  @moduledoc false

  # A company's status is a lifecycle, not an attribute. Each operation here
  # is one business event with a fixed origin and destination, a capability
  # check, an optional reason, and an audit action that records the intent
  # ("archived company") beside the captured field change. The public names
  # live on `Bilimbi.Core.Company`; the transition table is this module's
  # `@transitions`, and `docs/README.md` "Lifecycle" is its prose.
  #
  # Archived is final. Nothing leaves it: `apps/core/AGENTS.md` records that
  # archiving a company is not undone, so no operation reads from it. Pending
  # is an initial state only: a company is created pending or active
  # (`Schema.initial_statuses/0`), and `activate` is the one way out.

  import Ecto.Query

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.Schema
  alias Bilimbi.Core.Company.Summary
  alias Bilimbi.Core.Company.TenantPrimaryCompany

  @type operation :: :archive | :suspend | :activate | :reactivate
  @type error ::
          :not_found
          | :forbidden
          | :reason_too_long
          | :invalid_reason
          | :primary_company
          | :own_company
          | :audit_unavailable
          | {:invalid_transition, String.t()}

  @capability "admin.company.update"
  @reason_max_length 500

  # operation => {from statuses, to status, audit event}
  @transitions %{
    archive: {~w(pending active suspended), "archived", "company.archived"},
    suspend: {~w(active), "suspended", "company.suspended"},
    activate: {~w(pending), "active", "company.activated"},
    reactivate: {~w(suspended), "active", "company.reactivated"}
  }

  # The operations that take a company out of service. The tenant's primary
  # company and the company the performing account signed in under are what
  # the tenant and the operator stand on, so neither may be taken out.
  @guarded [:archive, :suspend]

  @operations Map.keys(@transitions) |> Enum.sort()

  @doc "The transition table: operation => {from statuses, to status, audit event}."
  @spec transitions() :: %{operation() => {[String.t()], String.t(), String.t()}}
  def transitions, do: @transitions

  @spec operations() :: [operation()]
  def operations, do: @operations

  @doc "The operations a company in `status` may undergo, in a fixed order."
  @spec operations_from(String.t()) :: [operation()]
  def operations_from(status) when is_binary(status) do
    for operation <- [:activate, :reactivate, :suspend, :archive],
        {from, _to, _event} = Map.fetch!(@transitions, operation),
        status in from,
        do: operation
  end

  @spec capability() :: String.t()
  def capability, do: @capability

  @spec reason_max_length() :: pos_integer()
  def reason_max_length, do: @reason_max_length

  @spec apply(operation(), Scope.t(), term(), keyword()) :: {:ok, Summary.t()} | {:error, error()}
  def apply(operation, %Scope{} = scope, company_id, opts)
      when operation in @operations and is_integer(company_id) and company_id > 0 and
             is_list(opts) do
    with {:ok, actor} <- performing_actor(scope),
         :ok <- authorize(scope),
         {:ok, reason} <- normalize_reason(Keyword.get(opts, :reason)) do
      Repo.transaction(fn ->
        with {:ok, company} <- lock_live_company(scope, company_id),
             :ok <- check_transition(operation, company.status),
             :ok <- check_standing(operation, scope, actor, company),
             {:ok, updated} <- Repo.update(Schema.transition_changeset(company, to(operation))),
             :ok <- record(scope, actor, operation, company, updated, reason) do
          Summary.from_schema(updated)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def apply(operation, %Scope{}, _company_id, opts)
      when operation in @operations and is_list(opts),
      do: {:error, :not_found}

  # A business event names who performed it. A system scope that names nobody
  # (seeds, `Tenancy.scope/1`) is refused; a named system principal is a
  # recorded identity and is decided by Authz like a person.
  defp performing_actor(%Scope{} = scope) do
    actor = Scope.actor(scope)

    if TenancyActor.system?(actor) and is_nil(TenancyActor.system_principal(actor)) do
      {:error, :forbidden}
    else
      {:ok, actor}
    end
  end

  defp authorize(%Scope{} = scope) do
    case Authz.can(scope, @capability) do
      %{allowed: true} -> :ok
      %{allowed: false} -> {:error, :forbidden}
    end
  end

  defp normalize_reason(nil), do: {:ok, nil}

  defp normalize_reason(reason) when is_binary(reason) do
    trimmed = String.trim(reason)

    cond do
      trimmed == "" -> {:ok, nil}
      String.length(trimmed) > @reason_max_length -> {:error, :reason_too_long}
      true -> {:ok, trimmed}
    end
  end

  defp normalize_reason(_other), do: {:error, :invalid_reason}

  # The row is locked so the transition is judged against the status that
  # will actually be overwritten, not one read a moment earlier.
  defp lock_live_company(%Scope{} = scope, company_id) do
    query =
      from(company in Tenancy.scope_query(Schema, scope),
        where: company.id == ^company_id and is_nil(company.deleted_at),
        lock: "FOR UPDATE"
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      %Schema{} = company -> {:ok, company}
    end
  end

  defp check_transition(operation, status) do
    {from, _to, _event} = Map.fetch!(@transitions, operation)

    if status in from, do: :ok, else: {:error, {:invalid_transition, status}}
  end

  defp check_standing(operation, %Scope{} = scope, actor, %Schema{} = company)
       when operation in @guarded do
    cond do
      primary_company?(scope, company.id) -> {:error, :primary_company}
      actor.company_id == company.id -> {:error, :own_company}
      true -> :ok
    end
  end

  defp check_standing(_operation, _scope, _actor, _company), do: :ok

  defp primary_company?(%Scope{} = scope, company_id) do
    TenantPrimaryCompany
    |> Tenancy.scope_query(scope)
    |> where([primary], primary.company_id == ^company_id)
    |> Repo.exists?()
  end

  defp to(operation), do: @transitions |> Map.fetch!(operation) |> elem(1)
  defp event(operation), do: @transitions |> Map.fetch!(operation) |> elem(2)

  # One retained action per event, in the same transaction as the status
  # write: a lifecycle change without its intent on record is rolled back.
  # The captured mutation still records the field values; this row says why
  # they changed. The request context (address, URL, trace) is what the web
  # edge put on this process, as the impersonation records use it.
  defp record(scope, actor, operation, before, updated, reason) do
    context = AuditContext.get()

    attributes = %{
      company_id: before.id,
      actor_type: Atom.to_string(actor.type),
      actor_id: actor.user_id || 0,
      impersonator_id: actor.impersonator_id,
      system_principal: actor.system_principal,
      ip_address: context.ip_address,
      url: context.url,
      user_agent: context.user_agent && String.slice(context.user_agent, 0, 80),
      trace_id: context.trace_id && String.slice(context.trace_id, 0, 12),
      event: event(operation),
      payload: %{
        "semantic" => true,
        "source" => "Company",
        "summary" => summary(operation, before),
        "subject" => %{"name" => "company", "id" => before.id, "label" => before.name},
        "context" => %{
          "from_status" => before.status,
          "to_status" => updated.status,
          "reason" => reason
        },
        "result" => "succeeded"
      },
      is_retained: true,
      occurred_at: NaiveDateTime.utc_now()
    }

    case Audit.record_action(scope, attributes) do
      {:ok, _action} -> :ok
      {:error, _changeset} -> {:error, :audit_unavailable}
    end
  end

  defp summary(operation, %Schema{name: name}) do
    "#{past_tense(operation)} company “#{name}”"
  end

  defp past_tense(:archive), do: "Archived"
  defp past_tense(:suspend), do: "Suspended"
  defp past_tense(:activate), do: "Activated"
  defp past_tense(:reactivate), do: "Reactivated"
end
