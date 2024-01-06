defmodule FrogWeb.Router do
  use FrogWeb, :router

  use Plug.ErrorHandler

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
    case reason do
      %Phoenix.Router.NoRouteError{} ->
        # this is a 404, so let's just ignore it
        :ok

      _ ->
        event_pid = PhoenixEvents.pid_to_event(self())

        if event_pid != nil do
          trace = Exception.format(kind, reason, stack)
          PhoenixEvents.Event.add_error(event_pid, trace)
        end
    end

    conn
  end

  def set_action(conn, _opts) do
    event_pid = PhoenixEvents.pid_to_event(self())

    if event_pid != nil do
      case conn.private do
        %{phoenix_live_view: {action, _, _}} ->
          PhoenixEvents.Event.set_action(event_pid, action)

        %{phoenix_router: router} ->
          case Phoenix.Router.route_info(router, conn.method, conn.request_path, conn.host) do
            %{plug: plug} ->
              PhoenixEvents.Event.set_action(event_pid, plug)

            _ ->
              :ok
          end

        _ ->
          :ok
      end
    end

    conn
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {FrogWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers

    plug :set_action
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FrogWeb do
    pipe_through :browser

    live "/", Index
    live "/event/:id/:type/:index", Event
    live "/events/:id/:type/:index", Events
  end

  # Other scopes may use custom stacks.
  # scope "/api", FrogWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FrogWeb.Telemetry
    end
  end
end
