defmodule FrogWeb.Event do
  use Phoenix.LiveView
  import Ecto.Query, only: [from: 2]
  import Phoenix.HTML.Form
  alias FrogWeb.Router.Helpers, as: Routes

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

    event = Frog.Repo.one(query) |> Jason.decode!() |> IO.inspect()

    socket =
      socket
      |> assign(:type, params["type"])
      |> assign(
        :trace,
        Enum.fetch!(event["tuning"]["#{params["type"]}s"], params["index"] |> String.to_integer())
      )
      |> assign(:event, Jason.encode!(event, pretty: true))

    {:noreply, socket}
  end
end
