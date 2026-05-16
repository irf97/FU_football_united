defmodule FuWeb.Router do
  use FuWeb, :router

  import FuWeb.PlayerAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FuWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_player
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public: phone-OTP login (spec §2.13 Surface 1)
  scope "/", FuWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    live_session :public, on_mount: [] do
      live "/login", LoginLive, :index
    end
  end

  scope "/", FuWeb do
    pipe_through :browser

    get "/session/:token", SessionController, :create
    delete "/session", SessionController, :delete
  end

  # Authenticated player surfaces (spec §2.13)
  scope "/", FuWeb do
    pipe_through [:browser, :require_authenticated]

    live_session :authenticated,
      on_mount: [{FuWeb.PlayerAuth, :require_authenticated}] do
      live "/", HomeLive, :index
      live "/browse", BrowseLive, :index
      live "/queue/:queue_id/chat", QueueChatLive, :index
      live "/lobby/:queue_id", LobbyLive, :index
      live "/postmatch/:queue_id", PostMatchLive, :index
      live "/profile", ProfileLive, :index
    end
  end

  if Application.compile_env(:fu, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: FuWeb.Telemetry
    end
  end
end
