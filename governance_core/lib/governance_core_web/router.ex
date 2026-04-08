defmodule GovernanceCoreWeb.Router do
  use GovernanceCoreWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {GovernanceCoreWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", GovernanceCoreWeb do
    pipe_through(:browser)

    live("/", SwarmHubLive)
    live("/personas", PersonaDirectoryLive)
    live("/scenarios", ScenarioBoardLive)
    live("/governance", GovernanceLive)
    
    # Legacy / Utility
    live("/agent/connect", AgentConnectLive)
    live("/agents/new", AgentCreateLive)
    live("/agents/:id", AgentDetailLive)
  end

  scope "/.well-known", GovernanceCoreWeb do
    pipe_through(:api)

    get("/agent.json", AgentDiscoveryController, :show)
  end

  scope "/api", GovernanceCoreWeb do
    pipe_through(:api)

    # Agent CRUD
    get("/agents", Api.AgentController, :index)
    get("/agents/:id", Api.AgentController, :show)
    post("/agents", Api.AgentController, :create)

    # Tasks
    post("/tasks", Api.TaskController, :create)
    get("/tasks/:id", Api.TaskController, :show)

    # Comments (from remote — Jules/Comment Monitor)
    post("/comments", CommentController, :create)
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:governance_core, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: GovernanceCoreWeb.Telemetry)
    end
  end
end
