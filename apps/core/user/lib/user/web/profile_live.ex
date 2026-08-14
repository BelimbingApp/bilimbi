defmodule Bilimbi.Core.User.Web.ProfileLive do
  @moduledoc """
  The signed-in account's own name, email and landing page.

  Ports Belimbing's `app/Core/User/Livewire/Settings/Profile.php`. Note what it
  is *not*: a generated settings form. Two of its three fields are columns on
  `users`, so the settings engine is the wrong tool and only the landing page
  goes through it.

  Three things this screen deliberately does not do:

    * **It never takes a user id from the request.** `User.update_user/4` is
      admin-shaped and will happily edit anyone in the tenant, so the id comes
      from the session and nowhere else. A self-service page that accepted an
      id from a form would be an unaudited admin edit with no capability check.

    * **It does not touch email verification.** `Schema.update_changeset/2`
      clears `email_verified_at` when the address changes, exactly as Belimbing
      does. A LiveView reaching in to clear it would be a second copy of an
      authentication rule, and the two would eventually disagree.

    * **It does not offer a free-text landing page.** Belimbing validates that
      field against the menu the user can actually reach; anything else lets
      someone pin a page they cannot open and meet a redirect loop on every
      sign-in. `Base.UI.Nav.tree/1` already returns exactly the reachable,
      route-verified set.
  """

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Base.Settings
  alias Bilimbi.Core.User
  alias Ecto.Changeset

  @landing_key "ui.landing_menu_id"
  @field_types %{name: :string, email: :string, landing_menu_id: :string}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Profile")
     |> assign(:landing_options, landing_options(socket))
     |> load_form()}
  end

  @impl true
  def handle_event("validate", %{"profile" => params}, socket) do
    {:noreply, assign_form(socket, form_changeset(params, socket))}
  end

  @impl true
  def handle_event("save", %{"profile" => params}, socket) do
    changeset = form_changeset(params, socket)

    if changeset.valid? do
      save(socket, changeset)
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, changeset) do
    scope = socket.assigns.current_scope.scope
    %{id: user_id, company_id: company_id} = account(socket)

    attributes = %{
      name: get_field(changeset, :name),
      email: get_field(changeset, :email)
    }

    case User.update_user(scope, company_id, user_id, attributes) do
      {:ok, _summary} ->
        {:noreply, save_landing(socket, changeset, attributes)}

      {:error, %Changeset{} = domain} ->
        {:noreply, assign_form(socket, copy_domain_errors(changeset, domain))}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Profile was not saved (#{reason}).")
         |> load_form()}
    end
  end

  # The landing page is a setting, so it goes through the settings engine
  # rather than beside the user columns -- which is what makes an empty
  # selection *clear* the override instead of pinning an empty string.
  defp save_landing(socket, changeset, attributes) do
    scope = settings_scope(socket)
    fields = Settings.Form.fields(["profile.profile"], scope)
    submitted = %{@landing_key => get_field(changeset, :landing_menu_id) || ""}

    case Settings.Form.save(submitted, fields, scope) do
      {:ok, _outcome} ->
        socket
        |> put_flash(:info, saved_message(socket, attributes))
        |> load_form()

      {:error, _key, message} ->
        socket
        |> put_flash(:error, "Landing page was not saved: #{message}")
        |> load_form()
    end
  end

  # Belimbing tells the user when an email change costs them their verified
  # status. Saying "Profile saved" and silently unverifying them is the kind of
  # quiet consequence that turns into a support ticket.
  defp saved_message(socket, %{email: email}) do
    if email != account(socket).email do
      "Profile saved. Your new address is unverified until you confirm it."
    else
      "Profile saved."
    end
  end

  defp load_form(socket) do
    account = account(socket)

    socket
    |> assign(:account, account)
    |> assign_form(
      form_changeset(
        %{
          "name" => account.name,
          "email" => account.email,
          "landing_menu_id" => current_landing(socket)
        },
        socket
      )
    )
  end

  defp current_landing(socket) do
    Settings.get(@landing_key, settings_scope(socket)) || ""
  end

  # The user's own scope: this screen edits nobody else's preferences.
  defp settings_scope(socket) do
    %{id: user_id, company_id: company_id} = account(socket)
    tenant_id = socket.assigns.current_scope.scope.tenant.id
    Settings.Scope.user(user_id, company_id, tenant_id)
  end

  # From the session, never from params. See the moduledoc.
  defp account(socket) do
    user = socket.assigns.current_scope.user

    %{
      # "user_id", not "id" -- the session map's key, as show_live.ex:40 uses.
      id: user["user_id"],
      company_id: user["company_id"],
      name: user["name"],
      email: user["email"]
    }
  end

  # Exactly the pages this actor can reach, so a landing page cannot be set to
  # somewhere that redirects them straight back out.
  defp landing_options(socket) do
    socket.assigns.current_scope
    |> Bilimbi.Base.UI.Nav.tree()
    |> flatten()
    |> Enum.filter(& &1.route)
    |> Enum.map(&{&1.label, &1.id})
  end

  defp flatten(nodes), do: Enum.flat_map(nodes, &[&1.item | flatten(&1.children)])

  defp form_changeset(params, socket) do
    allowed = Enum.map(socket.assigns.landing_options, fn {_label, id} -> id end)

    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required([:name, :email])
    |> validate_length(:name, max: 255)
    |> validate_length(:email, max: 255)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/, message: "must be an email address")
    |> validate_landing(allowed)
    |> Map.put(:action, :validate)
  end

  defp validate_landing(changeset, allowed) do
    validate_change(changeset, :landing_menu_id, fn :landing_menu_id, value ->
      if value in ["", nil] or value in allowed,
        do: [],
        else: [landing_menu_id: "is not a page you can open"]
    end)
  end

  defp copy_domain_errors(form_changeset, %Changeset{} = domain) do
    domain.errors
    |> Enum.reduce(form_changeset, fn {field, {message, opts}}, acc ->
      if Map.has_key?(@field_types, field),
        do: add_error(acc, field, message, opts),
        else: add_error(acc, :name, "#{field} #{message}", opts)
    end)
    |> Map.put(:action, :update)
  end

  defp assign_form(socket, %Changeset{} = changeset),
    do: assign(socket, :form, to_form(changeset, as: :profile))
end
