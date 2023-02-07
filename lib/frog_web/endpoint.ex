defmodule FrogWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :frog

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_frog_key",
    signing_salt: "He/GPaTw"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :frog,
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :frog
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug FrogWeb.Router

  def call(conn, opts) do
    event_pid = make_event(conn)

    :telemetry.attach(
      "queries#{inspect(event_pid)}",
      [:frog, :repo, :query],
      &FrogWeb.Endpoint.handle_query/4,
      {event_pid}
    )

    ret =
      try do
        super(conn |> put_private(:event_pid, event_pid), opts)
      rescue
        e ->
          trace = Exception.format(:error, e, __STACKTRACE__)
          Frog.Event.add_error(event_pid, trace)
          {:should_raise, e}
      end

    :telemetry.detach("queries#{inspect(event_pid)}")
    Frog.Event.finalize(event_pid)
    Frog.Event.send(event_pid)
    Frog.Event.cleanup(event_pid)

    ret =
      case ret do
        {:should_raise, e} ->
          raise e

        _ ->
          ret
      end

    ret
  end

  defp make_event(conn) do
    the_request = "#{conn.method} #{conn.request_path}"

    the_request =
      if conn.query_string == "" do
        the_request
      else
        "#{the_request}?#{conn.query_string}"
      end

    {:ok, pid} =
      Frog.Event.start_link(%{
        persona: "frog",
        the_request: the_request
      })

    case conn.request_path do
      "/assets/" <> _ ->
        Frog.Event.set_action(pid, "static")

      "/phoenix" <> _ ->
        Frog.Event.set_action(pid, "phoenix-internal")

      _ ->
        :ok
    end

    pid
  end

  def handle_query(_, measurements, meta, {event_pid}) do
    # {meta.query, div(measurements.total_time, 1_000_000) } |> IO.inspect()
    Frog.Event.add_query(event_pid, {meta.query, div(measurements.total_time, 1_000_000)})
  end
end
