defmodule FuWeb.LoginLive do
  @moduledoc "Surface 1: phone → SMS OTP → session (spec §2.13)."
  use FuWeb, :live_view

  alias Fu.{Accounts, Admin}
  alias FuWeb.PlayerAuth

  @admin_password "boobs"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, step: :phone, phone: "", error: nil, dev_code: nil)}
  end

  @impl true
  def handle_event("send", %{"phone" => phone}, socket) do
    case Accounts.request_otp(phone) do
      {:ok, code} ->
        # v1: there is no SMS gateway, so surface the code for the demo.
        {:noreply, assign(socket, step: :code, phone: phone, error: nil, dev_code: code)}

      _ ->
        {:noreply, assign(socket, error: "Enter a valid phone number.")}
    end
  end

  def handle_event("verify", %{"code" => code}, socket) do
    case Accounts.verify_otp(socket.assigns.phone, String.trim(code)) do
      {:ok, player} ->
        token = PlayerAuth.login_token(player.id)
        {:noreply, redirect(socket, to: ~p"/session/#{token}")}

      {:error, _} ->
        {:noreply, assign(socket, error: "Wrong or expired code.")}
    end
  end

  def handle_event("show-admin", _, socket),
    do: {:noreply, assign(socket, step: :admin, error: nil)}

  def handle_event("admin-login", %{"password" => pw}, socket) do
    if String.downcase(String.trim(pw)) == @admin_password do
      case Admin.ensure_admin_player() do
        nil ->
          {:noreply, assign(socket, error: "No players yet — run the seed first.")}

        admin ->
          token = PlayerAuth.login_token(admin.id)
          {:noreply, redirect(socket, to: ~p"/session/#{token}?#{[to: "/admin"]}")}
      end
    else
      {:noreply, assign(socket, error: "Wrong password.")}
    end
  end

  def handle_event("back", _, socket),
    do: {:noreply, assign(socket, step: :phone, error: nil, dev_code: nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="pt-20 space-y-10">
        <div class="text-center space-y-4">
          <div class="text-caption fu-ink-soft">Football United</div>
          <h1 class="text-h1">
            where i am,<br />I am<span class="text-primary">...!</span>
          </h1>
        </div>

        <div class="fu-card p-6 space-y-4">
          <%= cond do %>
            <% @step == :phone -> %>
            <h2 class="fu-serif text-lg">Sign in</h2>
            <p class="fu-ink-soft text-sm">No passwords. We text you a code.</p>
            <.form for={%{}} phx-submit="send" class="space-y-3">
              <input
                type="tel"
                name="phone"
                value={@phone}
                placeholder="+31 6 1000 0001"
                autocomplete="tel"
                class="input input-bordered w-full bg-base-200"
                required
              />
              <button class="btn btn-primary w-full" type="submit">Send code</button>
            </.form>
          <% @step == :admin -> %>
            <h2 class="fu-serif text-lg">Admin access</h2>
            <p class="fu-ink-soft text-sm">Enter the management password.</p>
            <.form for={%{}} phx-submit="admin-login" class="space-y-3">
              <input
                type="password"
                name="password"
                placeholder="password"
                autocomplete="off"
                class="input input-bordered w-full bg-base-200"
                required
              />
              <button class="btn btn-primary w-full" type="submit">Enter dashboard</button>
              <button type="button" phx-click="back" class="btn btn-ghost btn-sm w-full">
                Back
              </button>
            </.form>
          <% true -> %>
            <h2 class="fu-serif text-lg">Enter code</h2>
            <p class="fu-ink-soft text-sm">Sent to {@phone}.</p>
            <div :if={@dev_code} class="text-xs font-mono text-secondary">
              demo code: {@dev_code}
            </div>
            <.form for={%{}} phx-submit="verify" class="space-y-3">
              <input
                type="text"
                name="code"
                inputmode="numeric"
                placeholder="6-digit code"
                class="input input-bordered w-full bg-base-200 tracking-[0.5em] text-center"
                required
              />
              <button class="btn btn-primary w-full" type="submit">Verify</button>
              <button type="button" phx-click="back" class="btn btn-ghost btn-sm w-full">
                Change number
              </button>
            </.form>
          <% end %>

          <p :if={@error} class="text-error text-sm">{@error}</p>
        </div>

        <button
          :if={@step != :admin}
          type="button"
          phx-click="show-admin"
          class="block mx-auto text-caption text-[var(--fu-warning)]"
        >
          Admin login
        </button>
      </div>
    </Layouts.app>
    """
  end
end
