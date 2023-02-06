defmodule Frog.WebsocketEvents do
  use GenServer

  @impl true
  def init(_) do
    :telemetry.attach(
      "websocket-events-hp-start",
      [:phoenix, :live_view, :handle_params, :start],
      &Frog.WebsocketEvents.ws_event/4,
      {self()}
    )

    :telemetry.attach(
      "websocket-events-hp-end",
      [:phoenix, :live_view, :handle_params, :stop],
      &Frog.WebsocketEvents.ws_event/4,
      {self()}
    )

    :telemetry.attach(
      "websocket-events-he-start",
      [:phoenix, :live_view, :handle_event, :start],
      &Frog.WebsocketEvents.ws_event/4,
      {self()}
    )

    :telemetry.attach(
      "websocket-events-he-end",
      [:phoenix, :live_view, :handle_event, :stop],
      &Frog.WebsocketEvents.ws_event/4,
      {self()}
    )

    {:ok, {%{}, %{}}}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def ws_event(name, measurements, %{socket: %{transport_pid: t}} = meta, {pid}) when t != nil do
    GenServer.call(pid, {:ws_event, name, measurements, meta})
  end

  def ws_event(_, _, _, _), do: :ok

  @impl true
  def handle_call(
        {:ws_event, [:phoenix, :live_view, kind, :start], _measurements, meta},
        _from,
        {events, processes}
      ) do
    the_request =
      case meta do
        %{uri: uri} ->
          [_, _, _, path] = uri |> String.split("/", parts: 4)
          "WS_GET /#{path}"

        %{event: event, socket: %{view: view, router: router}} ->
          route =
            Phoenix.Router.routes(router)
            |> Enum.find(fn
              %{plug_opts: ^view} -> true
              _ -> false
            end)

          "WS_POST #{route.path} #{event}"
      end

    {:ok, pid} =
      Frog.Event.start_link(%{
        persona: "frog",
        the_request: the_request
      })

    :telemetry.attach(
      "queries#{inspect(pid)}",
      [:frog, :repo, :query],
      &FrogWeb.Endpoint.handle_query/4,
      {pid}
    )

    action = "#{inspect(meta.socket.view)}"
    Frog.Event.set_action(pid, action)
    events = events |> Map.put(meta.socket.id, pid)
    ref = Process.monitor(meta.socket.root_pid)
    processes = processes |> Map.put(meta.socket.root_pid, {meta.socket.id, ref})
    {:reply, :ok, {events, processes}}
  end

  @impl true
  def handle_call(
        {:ws_event, [:phoenix, :live_view, kind, :stop], measurements, meta},
        _from,
        {events, processes}
      ) do
    {event_pid, events} = events |> Map.pop(meta.socket.id)
    {{_, ref}, processes} = processes |> Map.pop(meta.socket.root_pid)
    Process.demonitor(ref)
    :telemetry.detach("queries#{inspect(event_pid)}")
    Frog.Event.finalize(event_pid)
    Frog.Event.send(event_pid)
    Frog.Event.cleanup(event_pid)
    {:reply, :ok, {events, processes}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, {e, stacktrace}}, {events, processes}) do
    {{socket_id, _}, processes} = processes |> Map.pop(pid)
    {event_pid, events} = events |> Map.pop(socket_id)
    trace = Exception.format(:error, e, stacktrace)
    Frog.Event.add_error(event_pid, trace)
    :telemetry.detach("queries#{inspect(event_pid)}")
    Frog.Event.finalize(event_pid)
    Frog.Event.send(event_pid)
    Frog.Event.cleanup(event_pid)
    {:noreply, {events, processes}}
  end
end
