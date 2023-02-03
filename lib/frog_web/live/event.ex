defmodule FrogWeb.Event do
  use Phoenix.LiveView
  import Ecto.Query, only: [from: 2]

  @impl true
  def render(assigns) do
    ~H"""
    <a href="#" onclick="history.back();">&lt; Back</a>
    <h2><%= @type %></h2>
    <p>Stacktrace: <pre><%= @trace %></pre></p>
    <p>Full event: <pre><%= @event %></pre></p>
    """
  end

  @impl true
  def handle_params(params, _url, socket) do
    query =
      from e in Frog.Events,
        where: e.id == ^params["id"],
        select: e.event

    event = Frog.Repo.one(query)

    query =
      from ew in Frog.ErrorsWarnings,
        where:
          ew.event_id == ^params["id"] and ew.key == ^params["index"] and
            ew.type == ^params["type"],
        select: ew.item,
        limit: 1

    trace = Frog.Repo.one(query)

    socket =
      socket
      |> assign(:type, params["type"])
      |> assign(:trace, trace)
      |> assign(:event, Jason.Formatter.pretty_print(event))

    {:noreply, socket}
  end
end
