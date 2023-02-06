defmodule Frog.Event do
  use GenServer

  @impl true
  def init(%{
        persona: persona,
        the_request: the_request
      }) do
    {:ok,
     %{
       start: :os.system_time(:millisecond),
       finalized: false,
       sent: false,
       event: %{
         epoch: :os.system_time(:seconds),
         id: make_id(),
         persona: persona,
         tuning: %{
           nr_errors: 0,
           nr_warnings: 0,
           nr_queries: 0,
           wallclock_queries: 0,
           errors: [],
           unique_warnings: %{},
           the_request: the_request
         },
         volatile: %{
           queries: []
         }
       }
     }}
  end

  def cleanup(pid) do
    GenServer.stop(pid, :normal)
  end

  def finalize(pid) do
    GenServer.call(pid, :finalize)
  end

  def send(pid) do
    GenServer.call(pid, :send)
  end

  def set_action(pid, action) do
    GenServer.cast(pid, {:set_action, action |> String.replace(".", "-")})
  end

  def add_error(pid, error) do
    GenServer.cast(pid, {:add_error, error})
  end

  def add_warning(pid, warning) do
    GenServer.cast(pid, {:add_warning, warning})
  end

  def add_query(pid, query) do
    GenServer.cast(pid, {:add_query, query})
  end

  def start_link(data) do
    GenServer.start_link(__MODULE__, data, [])
  end

  @impl true
  def handle_cast({:set_action, action}, %{event: ev} = event) do
    {:noreply, %{event | event: ev |> Map.put(:action, action)}}
  end

  @impl true
  def handle_cast({:add_error, error}, %{event: %{tuning: tuning} = ev} = event) do
    {:noreply,
     %{
       event
       | event: %{
           ev
           | tuning: %{tuning | nr_errors: tuning.nr_errors + 1, errors: [error | tuning.errors]}
         }
     }}
  end

  @impl true
  def handle_cast({:add_warning, warning}, %{event: %{tuning: tuning} = ev} = event) do
    {:noreply,
     %{
       event
       | event: %{
           ev
           | tuning: %{
               tuning
               | nr_warnings: tuning.nr_warnings + 1,
                 unique_warnings:
                   tuning.unique_warnings
                   |> Map.put(warning, Map.get(tuning.unique_warnings, warning, 0) + 1)
             }
         }
     }}
  end

  @impl true
  def handle_cast(
        {:add_query, {query, wallclock}},
        %{event: %{tuning: tuning, volatile: volatile} = ev} = event
      ) do
    tuning = %{
      tuning
      | nr_queries: tuning.nr_queries + 1,
        wallclock_queries: tuning.wallclock_queries + wallclock
    }

    volatile = %{
      volatile
      | queries: [[wallclock, query] | volatile.queries]
    }

    {:noreply, %{event | event: %{ev | tuning: tuning, volatile: volatile}}}
  end

  @impl true
  def handle_call(:finalize, _from, %{finalized: true} = event), do: {:reply, :ok, event}

  @impl true
  def handle_call(:finalize, _from, event) do
    duration = :os.system_time(:millisecond) - event.start

    tuning =
      event.event.tuning
      |> Map.put(:wallclock_ms, duration)

    volatile = event.event.volatile
    v_queries = volatile.queries |> Enum.reverse()
    volatile = %{volatile | queries: v_queries}

    {:reply, :ok,
     %{
       event
       | finalized: true,
         event: Map.put(event.event, :tuning, tuning) |> Map.put(:volatile, volatile)
     }}
  end

  @impl true
  def handle_call(:send, _from, %{sent: true} = event), do: {:reply, :ok, event}
  @impl true
  def handle_call(:send, from, %{finalized: false} = event) do
    {_, _, event} = handle_call(:finalize, from, event)
    handle_call(:send, from, event)
  end

  def handle_call(:send, _from, event) do
    ev = event.event |> IO.inspect()
    event_json = Jason.encode!(ev)
    send_event(event_json)
    {:reply, :ok, %{event | sent: true}}
  end

  defp send_event(json) do
    port = Application.fetch_env!(:frog, :collector_port)
    host = Application.fetch_env!(:frog, :collector_host)

    :httpc.request(
      :post,
      {'http://#{host}:#{port}/event', [], 'application/json', json |> to_charlist()},
      [],
      []
    )
  end

  defp make_id() do
    binary = <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :erlang.unique_integer()::32
    >>

    Base.url_encode64(binary)
  end
end
