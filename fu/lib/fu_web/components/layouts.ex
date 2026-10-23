defmodule FuWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use FuWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_player, :map, default: nil
  attr :active, :atom, default: nil, doc: "active tab: :home | :browse | :hobbies | :profile"
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :experience, Fu.Experiences.for_player(assigns.current_player))

    ~H"""
    <div id="spontaan-shell" class="fu-shell" data-experience={@experience.key}>
      <div
        :if={Application.get_env(:fu, :environment) == :rehearsal}
        id="simulation-banner"
        role="status"
        class="border-b border-primary/40 bg-primary/10 px-4 py-3 text-sm text-primary"
      >
        Simulation · fictional people, places and equipment
      </div>
      <header class="flex items-center justify-between px-4 pt-6 pb-3">
        <a id="spontaan-brand" href="/explore" class="spontaan-wordmark" aria-label="Spontaan home">
          spontaan<span aria-hidden="true">✳</span>
        </a>
        <div class="flex items-center gap-3">
          <a :if={@current_player} href="/equipment" class="text-caption" aria-label="Your equipment">
            Equipment
          </a>
          <a
            :if={@current_player && @current_player.is_admin}
            href="/admin"
            class="text-caption text-[var(--fu-warning)]"
          >
            Admin
          </a>
          <span
            :if={@current_player && @active in [:home, :browse, :lobby, :match, :postmatch]}
            id="football-rank"
            class="text-mono fu-ink-soft"
          >
            rank {:erlang.float_to_binary(@current_player.rank, decimals: 0)}
          </span>
        </div>
      </header>

      <div class="spontaan-experience-strip">
        <span id="experience-identity" class="text-caption">{@experience.label}</span>
        <a :if={@current_player} href="/profile#experience-form" class="text-xs fu-ink-soft">Make it yours ↗</a>
      </div>

      <main class="px-4 pb-6 space-y-4">
        {render_slot(@inner_block)}
      </main>

      <nav :if={@current_player} class="fu-tabbar flex">
        <.tab href="/explore" icon="hero-globe-alt" label="Explore" active={@active == :explore} />
        <.tab :if={@experience.key == "football" || @active in [:home, :browse, :lobby, :match, :postmatch]} href="/" icon="hero-home" label="Football" active={@active == :home} />
        <.tab :if={@experience.key == "football" || @active in [:home, :browse, :lobby, :match, :postmatch]} href="/browse" icon="hero-magnifying-glass" label="Browse" active={@active == :browse} />
        <.tab href="/hobbies" icon="hero-sparkles" label="Hobbies" active={@active == :hobbies} />
        <.tab :if={@experience.key != "football" && @active not in [:home, :browse, :lobby, :match, :postmatch]} href="/equipment" icon="hero-cube" label="Equipment" active={@active == :equipment} />
        <.tab href="/profile" icon="hero-user" label="Profile" active={@active == :profile} />
      </nav>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp tab(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "flex-1 flex flex-col items-center gap-1 py-3",
        @active && "text-primary",
        !@active && "fu-ink-soft"
      ]}
    >
      <span
        aria-hidden="true"
        class={["h-1 w-1 rounded-full", @active && "bg-primary", !@active && "bg-transparent"]}
      />
      <.icon name={@icon} class="size-5" />
      <span class="text-[10px] font-mono uppercase tracking-[0.1em]">{@label}</span>
    </a>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
