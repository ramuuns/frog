defmodule FrogWeb.Events do
  use Phoenix.LiveView
  import Ecto.Query, only: [from: 2]
  import Phoenix.HTML.Form
  alias FrogWeb.Router.Helpers, as: Routes

  def render_form(assigns) do
    ~H"""
    <.form :let={f} for={:the_form} phx-submit="form_submit">
      <%= label(f, :from, "Interval") %>
      <%= select(
        f,
        :from,
        [
          {"15 minutes", 60 * 15},
          {"1 hour", 60 * 60},
          {"2 hours", 60 * 60 * 2},
          {"3 hours", 60 * 60 * 3},
          {"6 hours", 60 * 60 * 6},
          {"12 hours", 60 * 60 * 12},
          {"24 hours", 60 * 60 * 24},
          {"2 days", 60 * 60 * 24 * 2}
        ],
        value: @form_data["from"]
      ) %>
      <%= submit("Go") %>
    </.form>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= render_form(assigns) %>
    <a href={"/?from=#{@form_data["from"]}"}>&lt; Back</a>
    <h2><%= @type %></h2>
    <h3><%= @key %></h3>
    <table>
      <thead>
        <tr>
          <th>When</th>
          <th>The request</th>
          <th>Event</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={event <- @events}>
          <td><%= event.epoch |> DateTime.from_unix!() |> DateTime.to_string() %></td>
          <td><%= event.the_request %></td>
          <td><pre><%= @events_by_id |> Map.get(event.event_id) %></pre></td>
        </tr>
      </tbody>
    </table>
    """
  end

  @impl true
  def handle_params(params, _url, socket) do
    from =
      case params do
        %{"from" => from} -> from |> String.to_integer()
        _ -> 60 * 60 * 1
      end

    start = :os.system_time(:seconds) - from

    query =
      from ew in Frog.ErrorsWarnings,
        where: ew.type == ^params["type"] and ew.key == ^params["index"] and ew.epoch > ^start,
        order_by: [desc: ew.epoch]

    events = Frog.Repo.all(query)

    event_ids = events |> Enum.map(fn e -> e.event_id end)

    query =
      from e in Frog.Events,
        where: e.id in ^event_ids

    events_by_id =
      Frog.Repo.all(query)
      |> Enum.map(fn ev -> %{ev | event: ev.event |> Jason.Formatter.pretty_print()} end)
      |> Enum.reduce(%{}, fn %{id: event_id, event: ev}, ret -> ret |> Map.put(event_id, ev) end)

    [ev | _] = events
    key = to_key(ev.item)

    socket =
      socket
      |> assign(:type, params["type"])
      |> assign(:index, params["index"])
      |> assign(:event_id, params["event_id"])
      |> assign(:key, key)
      |> assign(:events_by_id, events_by_id)
      |> assign(:events, events)
      |> assign(:form_data, %{"from" => from})

    {:noreply, socket}
  end

  @impl true
  def handle_event("form_submit", params, socket) do
    {:noreply,
     socket
     |> push_patch(
       to:
         Routes.live_path(
           socket,
           __MODULE__,
           socket.assigns.event_id,
           socket.assigns.type,
           socket.assigns.index,
           params["the_form"]
         )
     )}
  end

  def to_key(str) do
    [key | _] = str |> String.split("\n")
    key
  end
end
