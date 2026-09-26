defmodule Bilimbi.Base.Tenancy.ActorSeal do
  @moduledoc false
  # The seal that makes a scope's actor unforgeable by data.
  #
  # A seal is an HMAC over the actor and the tenant it was issued for, keyed by
  # `:bilimbi_base_tenancy, :actor_secret`. A struct literal, a struct update,
  # or an actor copied onto another tenant's scope fails `verify!/2`. The same
  # secret signs delegation tokens, the only form in which an actor leaves the
  # VM: a queued job acting for a user.
  #
  # Only `Scope` and `Authentication` call this module. The boundary test in
  # the Web host (`scope_actor_boundary_test.exs`) fails the build for any
  # other caller, because in one VM a function is callable by anyone and the
  # fence has to be checked rather than assumed.

  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.ForgedActorError
  alias Bilimbi.Base.Tenancy.Identity

  @seal_salt "bilimbi.tenancy.actor.seal.v1"
  @delegation_salt "bilimbi.tenancy.actor.delegation.v1"
  @minimum_secret_bytes 32

  @spec system(Identity.t()) :: Actor.t()
  def system(%Identity{id: tenant_id}) do
    %Actor{type: :system, seal: seal(tenant_id, :system, nil, nil, nil)}
  end

  @spec user(Identity.t(), pos_integer(), pos_integer(), pos_integer() | nil) :: Actor.t()
  def user(%Identity{id: tenant_id}, user_id, company_id, impersonator_id)
      when is_integer(user_id) and user_id > 0 and is_integer(company_id) and company_id > 0 and
             (is_nil(impersonator_id) or (is_integer(impersonator_id) and impersonator_id > 0)) do
    %Actor{
      type: :user,
      user_id: user_id,
      company_id: company_id,
      impersonator_id: impersonator_id,
      seal: seal(tenant_id, :user, user_id, company_id, impersonator_id)
    }
  end

  @spec verify!(term(), pos_integer()) :: Actor.t()
  def verify!(
        %Actor{
          type: type,
          user_id: user_id,
          company_id: company_id,
          impersonator_id: impersonator_id,
          seal: supplied
        } = actor,
        tenant_id
      )
      when type in [:user, :system] and is_binary(supplied) do
    expected = seal(tenant_id, type, user_id, company_id, impersonator_id)

    # hash_equals/2 compares in constant time but only equal-length binaries.
    if byte_size(expected) == byte_size(supplied) and :crypto.hash_equals(expected, supplied) and
         well_formed?(actor) do
      actor
    else
      raise ForgedActorError
    end
  end

  def verify!(_actor, _tenant_id), do: raise(ForgedActorError)

  @spec sign_delegation(pos_integer(), Actor.t()) :: binary()
  def sign_delegation(tenant_id, %Actor{type: :user} = actor) do
    Plug.Crypto.sign(
      secret!(),
      @delegation_salt,
      {tenant_id, actor.user_id, actor.company_id, actor.impersonator_id}
    )
  end

  @spec verify_delegation(binary(), pos_integer()) ::
          {:ok, {pos_integer(), pos_integer(), pos_integer(), pos_integer() | nil}}
          | {:error, :invalid | :expired}
  def verify_delegation(token, max_age) when is_binary(token) do
    case Plug.Crypto.verify(secret!(), @delegation_salt, token, max_age: max_age) do
      {:ok, {tenant_id, user_id, company_id, impersonator_id} = claims}
      when is_integer(tenant_id) and is_integer(user_id) and is_integer(company_id) and
             (is_nil(impersonator_id) or is_integer(impersonator_id)) ->
        {:ok, claims}

      {:ok, _other} ->
        {:error, :invalid}

      {:error, :expired} ->
        {:error, :expired}

      {:error, _reason} ->
        {:error, :invalid}
    end
  end

  defp well_formed?(%Actor{type: :system, user_id: nil, company_id: nil, impersonator_id: nil}),
    do: true

  defp well_formed?(%Actor{type: :user, user_id: user_id, company_id: company_id})
       when is_integer(user_id) and user_id > 0 and is_integer(company_id) and company_id > 0,
       do: true

  defp well_formed?(_actor), do: false

  defp seal(tenant_id, type, user_id, company_id, impersonator_id) do
    payload =
      :erlang.term_to_binary({tenant_id, type, user_id, company_id, impersonator_id}, [
        :deterministic
      ])

    :crypto.mac(:hmac, :sha256, seal_key(), payload)
  end

  # The secret is already high-entropy (production uses SECRET_KEY_BASE), so a
  # keyed hash separates the seal key from the delegation key without key
  # stretching, and needs no key cache: a mix task that builds scopes before
  # applications start seals them the same way.
  defp seal_key, do: :crypto.mac(:hmac, :sha256, secret!(), @seal_salt)

  defp secret! do
    case Application.get_env(:bilimbi_base_tenancy, :actor_secret) do
      secret when is_binary(secret) and byte_size(secret) >= @minimum_secret_bytes ->
        secret

      _missing ->
        raise ArgumentError,
              "config :bilimbi_base_tenancy, :actor_secret must be a secret of at least " <>
                "#{@minimum_secret_bytes} bytes; production derives it from SECRET_KEY_BASE"
    end
  end
end
