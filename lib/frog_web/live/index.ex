defmodule FrogWeb.Index do
  use Phoenix.LiveView
  import Ecto.Query, only: [from: 2]
  import Phoenix.HTML.Form
  alias FrogWeb.Router.Helpers, as: Routes

  @impl true
  def render(assigns) do
    ~H"""
    <%= render_form(assigns) %>
    <%= render_table(assigns) %>
    """
  end

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

  def render_table(assigns) do
    ~H"""
    <table class="main-errors-warnings-table">
      <thead>
        <tr>
          <th>Count</th>
          <th>When</th>
          <th>Personas</th>
          <th>Actions</th>
          <th>Type</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @the_table}>
          <td><%= row.count %></td>
          <td>
            <svg width="100" height="20">
              <rect
                :for={{bucket, index} <- Enum.with_index(row.time_buckets)}
                width="5"
                height={bucket * 20}
                x={index * 5}
                y={20 - bucket * 20}
                style="fill:rgb(255,0,0);stroke-width:0"
              />
            </svg>
          </td>
          <td>
            <span :for={persona <- row.personas}><%= persona %></span>
          </td>
          <td>
            <span :for={action <- row.actions}><%= action %></span>
          </td>
          <td><%= row.type %></td>
          <td>
            <.link navigate={
              Routes.live_path(@socket, FrogWeb.Event, row.event_id, row.type, row.key)
            }>
              View event
            </.link>
            <.link navigate={
              Routes.live_path(@socket, FrogWeb.Events, row.event_id, row.type, row.key, %{
                "from" => @form_data["from"]
              })
            }>
              View all events
            </.link>

            <pre><%= row.item %></pre>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @impl true
  def handle_params(params, _blah, socket) do
    params |> IO.inspect()

    from =
      case params do
        %{"from" => from} -> from |> String.to_integer()
        _ -> 60 * 60 * 1
      end

    start = :os.system_time(:seconds) - from

    query =
      from ew in Frog.ErrorsWarnings,
        where: ew.epoch > ^start,
        group_by: [ew.key, ew.type],
        select: %{
          count: sum(ew.cnt),
          key: ew.key,
          type: ew.type,
          item: ew.item,
          event_id: ew.event_id
        }

    unique_ews = Frog.Repo.all(query)

    unique_errs =
      unique_ews
      |> Enum.filter(fn
        %{type: "error"} -> true
        _ -> false
      end)
      |> Enum.map(fn %{key: key} -> key end)

    unique_warns =
      unique_ews
      |> Enum.filter(fn
        %{type: "warning"} -> true
        _ -> false
      end)
      |> Enum.map(fn %{key: key} -> key end)

    w_query =
      from ew in Frog.ErrorsWarnings,
        where: ew.type == "warning" and ew.key in ^unique_warns and ew.epoch > ^start,
        select: %{
          type: ew.type,
          key: ew.key,
          cnt: ew.cnt,
          epoch: ew.epoch,
          persona: ew.persona,
          action: ew.action
        }

    query =
      from ew in Frog.ErrorsWarnings,
        where: ew.type == "error" and ew.key in ^unique_errs and ew.epoch > ^start,
        select: %{
          type: ew.type,
          key: ew.key,
          cnt: ew.cnt,
          epoch: ew.epoch,
          persona: ew.persona,
          action: ew.action
        },
        union: ^w_query

    ew_times = Frog.Repo.all(query)

    the_end = :os.system_time(:seconds)

    bucket_size = div(the_end - start, 20)

    ew_grouped =
      ew_times
      |> Enum.reduce(%{}, fn %{
                               action: action,
                               persona: persona,
                               key: key,
                               cnt: cnt,
                               type: type,
                               epoch: epoch
                             },
                             ret ->
        %{
          buckets: buckets,
          personas: personas,
          actions: actions
        } =
          ret
          |> Map.get({key, type}, %{
            buckets: {
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0
            },
            personas: MapSet.new(),
            actions: MapSet.new()
          })

        bucket = div(epoch - start, bucket_size)
        buckets = buckets |> put_elem(bucket, elem(buckets, bucket) + cnt)

        ret
        |> Map.put({key, type}, %{
          buckets: buckets,
          personas: personas |> MapSet.put(persona),
          actions: actions |> MapSet.put(action)
        })
      end)

    unique_ews =
      unique_ews
      |> Enum.map(fn
        %{type: type, key: key} = ew ->
          %{
            buckets: buckets,
            personas: personas,
            actions: actions
          } = ew_grouped |> Map.get({key, type})

          ew
          |> Map.put(:time_buckets, buckets |> Tuple.to_list() |> normalize)
          |> Map.put(:personas, personas |> MapSet.to_list() |> Enum.sort())
          |> Map.put(:actions, actions |> MapSet.to_list() |> Enum.sort())
      end)
      |> Enum.sort_by(& &1.count, :desc)

    form_data = %{
      "from" => from
    }

    socket =
      socket
      |> assign(:the_table, unique_ews)
      |> assign(:form_data, form_data)

    {:noreply, socket}
  end

  @impl true
  def handle_event("form_submit", params, socket) do
    {:noreply, socket |> push_patch(to: Routes.live_path(socket, __MODULE__, params["the_form"]))}
  end

  defp normalize(list) do
    max = Enum.max(list)
    list |> Enum.map(fn i -> i / max end)
  end
end
