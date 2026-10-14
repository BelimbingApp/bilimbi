defmodule Bilimbi.Core.AgentAccess do
  @moduledoc """
  A person's OAuth grants, never a second identity. Codes and tokens are stored
  only as SHA-256 hashes. Row locks serialize approval, redemption, rotation,
  replay and revocation; spent refresh hashes remain so replay ends the grant.
  Authentication is proven afresh at the Web edge; this module returns claims,
  not an authenticated scope. Self-service management refuses impersonation and
  agent facets. A stated agent ID labels a request and never authenticates it.
  """
  import Ecto.Query
  alias Bilimbi.Base.{Repo, Settings, Tenancy}
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.AgentAccess.{AuthorizationCode, Connection, Device, OAuthClient, Token}
  alias Bilimbi.Core.{Company, User}

  @client "bilimbi-native"
  @unstated "(not stated)"
  @seen_limit 20
  def client_id, do: @client
  def device_grant, do: "urn:ietf:params:oauth:grant-type:device_code"

  @doc "Validates an operator-registered authorization-code request before displaying consent."
  defdelegate authorization_request(params, resource), to: OAuthClient, as: :request

  @doc "Creates a person-owned MCP grant only after explicit browser consent."
  def authorize(%Scope{} = scope, params, resource, expires_at) do
    with :ok <- self_service(scope),
         {:ok, request} <- OAuthClient.request(params, resource),
         true <- match?(%DateTime{}, expires_at) and DateTime.compare(expires_at, now()) == :gt do
      transaction(fn ->
        actor = Scope.actor(scope)

        {:ok, connection} =
          Repo.insert(
            Ecto.Changeset.change(%Connection{}, %{
              tenant_id: Scope.tenant_id(scope),
              company_id: actor.company_id,
              user_id: actor.user_id,
              agent_id: request["client_name"],
              client_id: request["client_id"],
              resource: resource,
              oauth_scope: "bilimbi",
              seen_agent_ids: %{},
              expires_at: DateTime.truncate(expires_at, :second)
            })
          )

        code = secret()

        {:ok, _} =
          Repo.insert(
            Ecto.Changeset.change(%AuthorizationCode{}, %{
              connection_id: connection.id,
              code_hash: hash(code),
              code_challenge: request["code_challenge"],
              redirect_uri: request["redirect_uri"],
              expires_at:
                DateTime.add(now(), Settings.get("agent_access.authorization_code_seconds"))
            })
          )

        {:ok, code}
      end)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_expiry}
    end
  end

  @doc "Redeems a short-lived code once, bound to client, callback, resource and S256 verifier."
  def exchange_code(params, resource) when is_map(params) do
    code = params["code"]

    with true <- is_binary(code) and byte_size(code) == 43,
         %AuthorizationCode{} = found <-
           Repo.one(from(c in AuthorizationCode, where: c.code_hash == ^hash(code))) do
      transaction(fn ->
        connection = locked_connection(found.connection_id)
        auth = Repo.get!(AuthorizationCode, found.id)

        client = Map.get(Settings.get("agent_access.oauth_clients"), connection.client_id)

        valid_client? =
          is_map(client) and auth.redirect_uri in client["redirect_uris"]

        cond do
          not valid_client? or connection.client_id != params["client_id"] or
            connection.resource != resource or params["resource"] != resource or
            auth.redirect_uri != params["redirect_uri"] or
            not OAuthClient.proof?(params["code_verifier"], auth.code_challenge) or
              DateTime.compare(auth.expires_at, now()) != :gt ->
            {:error, :invalid_grant}

          not is_nil(auth.used_at) ->
            Repo.update!(Ecto.Changeset.change(connection, revoked_at: now()))
            {:error, :invalid_grant}

          true ->
            with :ok <- live(connection) do
              Repo.update!(Ecto.Changeset.change(auth, used_at: now()))
              issue(connection)
            end
        end
      end)
    else
      _ -> {:error, :invalid_grant}
    end
  end

  def exchange_code(_, _), do: {:error, :invalid_request}

  def start_device(@client, agent_id) when is_binary(agent_id) do
    if valid_label?(agent_id) do
      device = secret()
      user = :crypto.strong_rand_bytes(5) |> Base.encode32(padding: false)
      user = binary_part(user, 0, 4) <> "-" <> binary_part(user, 4, 4)
      now = now()

      {:ok, _} =
        Repo.insert(
          Ecto.Changeset.change(%Device{}, %{
            device_hash: hash(device),
            user_hash: hash(user),
            client_id: @client,
            agent_id: agent_id,
            expires_at: DateTime.add(now, 600),
            next_poll_at: now,
            interval: 5,
            status: "pending"
          })
        )

      {:ok, %{device_code: device, user_code: user, expires_in: 600, interval: 5}}
    else
      {:error, :invalid_request}
    end
  end

  def start_device(@client, _), do: {:error, :invalid_request}
  def start_device(_, _), do: {:error, :invalid_client}

  def device(%Scope{} = scope, code) when is_binary(code) do
    with :ok <- self_service(scope),
         %Device{status: "pending"} = device <-
           Repo.one(from(d in Device, where: d.user_hash == ^hash(code))),
         true <- DateTime.compare(device.expires_at, now()) == :gt do
      {:ok, %{agent_id: device.agent_id, expires_at: device.expires_at}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_user_code}
    end
  end

  def decide(%Scope{} = scope, code, decision, expires_at) when decision in [:approve, :deny] do
    with :ok <- self_service(scope),
         true <- match?(%DateTime{}, expires_at) and DateTime.compare(expires_at, now()) == :gt do
      transaction(fn ->
        device =
          Repo.one(from(d in Device, where: d.user_hash == ^hash(code), lock: "FOR UPDATE"))

        cond do
          is_nil(device) or device.status != "pending" ->
            {:error, :invalid_user_code}

          DateTime.compare(device.expires_at, now()) != :gt ->
            {:error, :expired_token}

          decision == :deny ->
            {:ok, _} = Repo.update(Ecto.Changeset.change(device, status: "denied"))
            :ok

          true ->
            actor = Scope.actor(scope)

            {:ok, connection} =
              Repo.insert(
                Ecto.Changeset.change(%Connection{}, %{
                  tenant_id: Scope.tenant_id(scope),
                  company_id: actor.company_id,
                  user_id: actor.user_id,
                  agent_id: device.agent_id,
                  seen_agent_ids: %{},
                  expires_at: DateTime.truncate(expires_at, :second)
                })
              )

            {:ok, _} =
              Repo.update(
                Ecto.Changeset.change(device, status: "approved", connection_id: connection.id)
              )

            :ok
        end
      end)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_expiry}
    end
  end

  def exchange(@client, code) when is_binary(code) do
    transaction(fn ->
      device =
        Repo.one(from(d in Device, where: d.device_hash == ^hash(code), lock: "FOR UPDATE"))

      now = now()

      cond do
        is_nil(device) ->
          {:error, :invalid_grant}

        DateTime.compare(device.expires_at, now) != :gt ->
          {:error, :expired_token}

        device.status == "denied" ->
          {:error, :access_denied}

        device.status == "used" ->
          {:error, :invalid_grant}

        DateTime.compare(device.next_poll_at, now) == :gt ->
          interval = device.interval + 5

          {:ok, _} =
            Repo.update(
              Ecto.Changeset.change(device,
                interval: interval,
                next_poll_at: DateTime.add(now, interval)
              )
            )

          {:error, :slow_down}

        device.status == "pending" ->
          {:ok, _} =
            Repo.update(
              Ecto.Changeset.change(device, next_poll_at: DateTime.add(now, device.interval))
            )

          {:error, :authorization_pending}

        true ->
          connection = locked_connection(device.connection_id)

          with :ok <- live(connection) do
            {:ok, _} = Repo.update(Ecto.Changeset.change(device, status: "used"))
            issue(connection)
          end
      end
    end)
  end

  def exchange(@client, _), do: {:error, :invalid_request}
  def exchange(_, _), do: {:error, :invalid_client}

  def refresh(client, value, resource \\ nil)

  def refresh(client, value, resource) when is_binary(value) do
    # First locate the immutable parent, then lock parent before token everywhere.
    # Otherwise concurrent refresh and device redemption could invert lock order.
    case Repo.one(from(t in Token, where: t.token_hash == ^hash(value) and t.kind == "refresh")) do
      nil ->
        {:error, :invalid_grant}

      found ->
        transaction(fn ->
          connection = locked_connection(found.connection_id)
          token = Repo.get!(Token, found.id)

          cond do
            connection.client_id != client or connection.resource != resource ->
              {:error, :invalid_grant}

            client != @client and
                not Map.has_key?(Settings.get("agent_access.oauth_clients"), client) ->
              {:error, :invalid_client}

            not is_nil(token.used_at) ->
              {:ok, _} = Repo.update(Ecto.Changeset.change(connection, revoked_at: now()))
              {:error, :invalid_grant}

            DateTime.compare(token.expires_at, now()) != :gt ->
              {:error, :invalid_grant}

            true ->
              with :ok <- live(connection) do
                {:ok, _} = Repo.update(Ecto.Changeset.change(token, used_at: now()))
                issue(connection)
              end
          end
        end)
    end
  end

  def refresh(@client, _, _), do: {:error, :invalid_request}
  def refresh(_, _, _), do: {:error, :invalid_client}

  @doc "Opaque credential lookup before a tenant is known. Returns stable claims only."
  def authenticate(value, resource \\ nil) when is_binary(value) do
    case Repo.one(from(t in Token, where: t.token_hash == ^hash(value) and t.kind == "access")) do
      %Token{} = token ->
        with true <- DateTime.compare(token.expires_at, now()) == :gt,
             connection when not is_nil(connection) <- lockedless_connection(token.connection_id),
             true <- connection.resource == resource,
             :ok <- live_grant(connection) do
          {:ok, Map.take(connection, [:id, :tenant_id, :company_id, :user_id])}
        else
          _ -> {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  @doc """
  Records the stated identity sealed on an authenticated agent scope. A request
  that stated none is recorded as `"(not stated)"`. A changed identity is flagged,
  never refused; only the newest #{@seen_limit} distinct ones are kept.
  """
  def observe(%Scope{} = scope) do
    case Scope.actor(scope).facet do
      %{type: :agent, connection_id: id, agent_id: stated} ->
        label = stated || @unstated

        with %Connection{} = connection <- find_own(scope, id),
             :ok <- live_grant(connection) do
          if known?(connection, label), do: :ok, else: remember(scope, id, label)
        else
          _ -> {:error, :invalid_grant}
        end

      _ ->
        {:error, :invalid_grant}
    end
  end

  defp find_own(scope, id), do: own_query(scope) |> where([c], c.id == ^id) |> Repo.one()

  defp known?(connection, label),
    do: label == connection.agent_id or Map.has_key?(connection.seen_agent_ids, label)

  defp remember(scope, id, label) do
    transaction(fn ->
      connection =
        own_query(scope) |> where([c], c.id == ^id) |> lock("FOR UPDATE") |> Repo.one()

      with :ok <- live_grant(connection) do
        unless known?(connection, label) do
          newest =
            connection.seen_agent_ids
            |> Enum.sort_by(fn {name, at} -> {at, name} end, :desc)
            |> Enum.take(@seen_limit - 1)

          seen = Map.new([{label, DateTime.to_iso8601(DateTime.utc_now())} | newest])

          {:ok, _} = Repo.update(Ecto.Changeset.change(connection, seen_agent_ids: seen))
        end

        :ok
      end
    end)
  end

  def list_connections(%Scope{} = scope) do
    with :ok <- self_service(scope) do
      {:ok,
       own_query(scope)
       |> order_by([c], desc: c.id)
       |> Repo.all()
       |> Enum.map(&Map.take(&1, [:id, :agent_id, :seen_agent_ids, :expires_at, :revoked_at]))}
    end
  end

  def revoke(%Scope{} = scope, id) do
    with :ok <- self_service(scope) do
      {count, _} =
        own_query(scope)
        |> where([c], c.id == ^id and is_nil(c.revoked_at))
        |> Repo.update_all(set: [revoked_at: now()])

      if count == 1, do: :ok, else: {:error, :not_found}
    end
  end

  def valid_label?(label),
    do:
      is_binary(label) and byte_size(label) in 1..255 and String.printable?(label) and
        String.trim(label) != ""

  defp own_query(scope) do
    actor = Scope.actor(scope)

    Tenancy.scope_query(Connection, scope)
    |> where([c], c.user_id == ^actor.user_id and c.company_id == ^actor.company_id)
  end

  defp self_service(scope) do
    case Scope.actor(scope) do
      %{type: :user, impersonator_id: nil, facet: nil} -> :ok
      _ -> {:error, :person_required}
    end
  end

  # A token/code proves which grant to look up before any tenant scope exists.
  # This bounded credential lookup is the only unscoped connection read.
  defp lockedless_connection(id), do: Repo.one(from(c in Connection, where: c.id == ^id))

  defp locked_connection(id),
    do: Repo.one(from(c in Connection, where: c.id == ^id, lock: "FOR UPDATE"))

  defp live_grant(nil), do: {:error, :invalid_grant}

  defp live_grant(connection) do
    if is_nil(connection.revoked_at) and DateTime.compare(connection.expires_at, now()) == :gt,
      do: :ok,
      else: {:error, :invalid_grant}
  end

  # Token issuance has no caller scope yet. Resolve live identity here;
  # authenticated requests resolve it once in AgentAuth, then observe uses
  # only its sealed scope and the grant's state, never another tenant resolver.
  defp live(connection) do
    with :ok <- live_grant(connection),
         {:ok, tenant_id} <- Company.fetch_tenant_id_for_company(connection.company_id),
         true <- tenant_id == connection.tenant_id,
         {:ok, scope} <- Tenancy.scope(tenant_id),
         {:ok, _} <- User.get_user(scope, connection.company_id, connection.user_id) do
      :ok
    else
      _ -> {:error, :invalid_grant}
    end
  end

  defp issue(connection) do
    access = secret()
    refresh = secret()
    expiry = Enum.min_by([connection.expires_at, DateTime.add(now(), 3600)], &DateTime.to_unix/1)

    for {value, kind, expires} <- [
          {access, "access", expiry},
          {refresh, "refresh", connection.expires_at}
        ] do
      {:ok, _} =
        Repo.insert(
          Ecto.Changeset.change(%Token{},
            connection_id: connection.id,
            token_hash: hash(value),
            kind: kind,
            expires_at: expires
          )
        )
    end

    result = %{
      access_token: access,
      refresh_token: refresh,
      token_type: "Bearer",
      expires_in: max(DateTime.diff(expiry, now()), 0)
    }

    {:ok,
     if(connection.oauth_scope, do: Map.put(result, :scope, connection.oauth_scope), else: result)}
  end

  # OAuth errors such as pending/slow_down and replay must commit their state.
  defp transaction(fun) do
    {:ok, result} = Repo.transaction(fun)
    result
  end

  defp secret, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  defp hash(value), do: :crypto.hash(:sha256, value)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
