defmodule BilimbiWeb.Impersonation do
  @moduledoc """
  Switches a signed-in administrator into another account in the same
  workspace, and restores the administrator afterwards.

  The durable session row stays the one `BilimbiWeb.UserAuth` opened. This
  module records the transition and rewrites the cookie. The controller is
  `BilimbiWeb.ImpersonationController`.
  """

  import Plug.Conn
  import Phoenix.Controller

  require Logger

  use BilimbiWeb, :verified_routes

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Summary
  alias BilimbiWeb.UserAuth

  @doc """
  Switches the active session to `target_user` and records the administrator's
  identity in the impersonation cookie payload. Updates the durable session
  row in place without leaving stranded authentication records.

  The switch is recorded once it has happened: a retained `impersonation.started`
  action names the operator as the actor and the target as the subject. The
  record is best-effort, so a trail that cannot be written never undoes a
  switch that already took effect.
  """
  def impersonate_user(
        conn,
        %{"user_id" => original_user_id, "name" => original_user_name} = original_user,
        %Summary{} = target_user
      )
      when is_integer(original_user_id) and is_binary(original_user_name) do
    current_id = UserAuth.current_session_id(conn)
    scope = conn.assigns[:current_scope] && conn.assigns[:current_scope].scope

    with %Scope{} <- scope,
         {:ok, _target_session_user} <- UserAuth.session_user(target_user),
         {:ok, session_id} <-
           UserAuth.persist_durable_session(
             conn,
             target_user.id,
             target_user.company_id,
             current_id
           ) do
      record_impersonation(scope, "impersonation.started", %{
        operator_id: original_user_id,
        company_id: original_user["company_id"],
        target_id: target_user.id,
        summary: "Started impersonating #{target_user.name}"
      })

      conn
      |> configure_session(renew: true)
      |> put_session(UserAuth.impersonation_key(), %{
        "original_user_id" => original_user_id,
        "original_user_name" => original_user_name
      })
      |> put_session(UserAuth.session_key(), %{
        "session_id" => session_id,
        "user_id" => target_user.id,
        "company_id" => target_user.company_id
      })
      |> redirect(to: ~p"/dashboard")
    else
      _ ->
        conn
        |> put_flash(:error, "Unable to impersonate that user.")
        |> redirect(to: ~p"/users")
    end
  end

  @doc """
  Leaves impersonation by clearing the impersonation cookie and restoring the
  original administrator's authenticated session in place.

  A retained `impersonation.stopped` action names the operator as the actor
  once their own session is restored. Leaving must always succeed — an
  operator is never trapped in a borrowed session — so a failed stop record
  is logged rather than blocking.
  """
  def leave_impersonation(conn) do
    case get_session(conn, UserAuth.impersonation_key()) do
      %{"original_user_id" => original_user_id} when is_integer(original_user_id) ->
        scope = conn.assigns[:current_scope] && conn.assigns[:current_scope].scope
        current_id = UserAuth.current_session_id(conn)
        impersonated_user_id = impersonated_user_id(conn)

        with %Scope{} <- scope,
             {:ok, %Summary{} = original_user} <- User.get_tenant_user(scope, original_user_id),
             {:ok, session_id} <-
               UserAuth.persist_durable_session(
                 conn,
                 original_user.id,
                 original_user.company_id,
                 current_id
               ) do
          record_impersonation(scope, "impersonation.stopped", %{
            operator_id: original_user.id,
            company_id: original_user.company_id,
            target_id: impersonated_user_id,
            summary: "Stopped impersonating"
          })

          conn
          |> configure_session(renew: true)
          |> delete_session(UserAuth.impersonation_key())
          |> put_session(UserAuth.session_key(), %{
            "session_id" => session_id,
            "user_id" => original_user.id,
            "company_id" => original_user.company_id
          })
          |> redirect(to: ~p"/dashboard")
        else
          _ ->
            UserAuth.log_out_user(conn)
        end

      _ ->
        redirect(conn, to: ~p"/dashboard")
    end
  end

  @doc false
  def extract_impersonator(%{
        "original_user_id" => id,
        "original_user_name" => name
      })
      when is_integer(id) and is_binary(name) do
    %{id: id, name: name}
  end

  def extract_impersonator(_), do: nil

  @doc false
  def impersonation_opts(nil, _session_id), do: []

  def impersonation_opts(%{id: impersonator_id}, session_id),
    do: [impersonator_id: impersonator_id, impersonation_session_id: session_id]

  defp impersonated_user_id(conn) do
    case get_session(conn, UserAuth.session_key()) do
      %{"user_id" => user_id} when is_integer(user_id) -> user_id
      _ -> nil
    end
  end

  # Belimbing's `ImpersonationManager` records both transitions as retained
  # semantic actions, and its recorder payload shape is mirrored here so both
  # trails read the same. The operator acts as themselves at each transition,
  # so `impersonator_id` is an explicit nil rather than inherited from the
  # request context — which, on stop, still names the operator as impersonator.
  # Request facts come from that same context, set by `fetch_current_scope/2`.
  #
  # Both transitions have already taken effect by the time they are recorded,
  # so recording is best-effort: a rejected changeset is logged, and a missing
  # actions table is the pre-canonical state `MutationCapture.insert_capture/1`
  # also tolerates. Neither ever fails the transition back out to the caller.
  defp record_impersonation(%Scope{} = scope, event, %{
         operator_id: operator_id,
         company_id: company_id,
         target_id: target_id,
         summary: summary
       }) do
    context = AuditContext.get()

    result =
      Audit.record_action(scope, %{
        company_id: company_id,
        actor_type: "user",
        actor_id: operator_id,
        impersonator_id: nil,
        ip_address: context.ip_address,
        url: context.url,
        user_agent: context.user_agent && String.slice(context.user_agent, 0, 80),
        trace_id: context.trace_id && String.slice(context.trace_id, 0, 12),
        event: event,
        payload: %{
          "semantic" => true,
          "source" => "Impersonation",
          "summary" => summary,
          "surface" => "admin.impersonate",
          "subject" => %{"name" => "user", "id" => target_id, "label" => "User##{target_id}"},
          "context" => %{"impersonator_id" => operator_id, "target_id" => target_id},
          "result" => "succeeded"
        },
        is_retained: true,
        occurred_at: NaiveDateTime.utc_now()
      })

    case result do
      {:ok, _action} ->
        :ok

      {:error, changeset} ->
        Logger.warning("#{event} audit action was not recorded: #{inspect(changeset.errors)}")

        :ok
    end
  rescue
    error in Postgrex.Error ->
      if match?(%{postgres: %{code: :undefined_table}}, error) do
        :ok
      else
        reraise error, __STACKTRACE__
      end
  end
end
