defmodule FrogWeb.Index do
  use Phoenix.LiveView
  import Ecto.Query, only: [from: 2]

  @impl true
  def render(assigns) do
    ~H"""

    <table>
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
          <td><%= row.count  %></td>
          <td>
            <svg width="100" height="20">
              <rect :for={ {bucket, index} <- Enum.with_index(row.time_buckets) } width="5" height={ bucket * 20 } x={ index * 5 } y={ 20 - bucket * 20 } style="fill:rgb(255,0,0);stroke-width:0" />
            </svg>
          </td>
          <td>
            <span :for={ persona <- row.personas }><%= persona %></span>
          </td>
          <td>
            <span :for={ action <- row.actions }><%= action %></span>
          </td>
          <td><%= row.type %></td>
          <td><pre><%= row.item %></pre></td>
        </tr>
      </tbody>
    </table>
    """
  end

  @impl true
  def mount(_params, _blah, socket) do
    start = :os.system_time(:seconds) - 60 * 60 * 1

    query =
      from ew in Frog.ErrorsWarnings,
        where: ew.epoch > ^start,
        group_by: [ew.key, ew.type],
        select: %{
          count: count(ew.event_id),
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
          epoch: ew.epoch,
          persona: ew.persona,
          action: ew.action
        },
        union: ^w_query

    ew_times = Frog.Repo.all(query) |> IO.inspect()

    the_end = :os.system_time(:seconds)

    bucket_size = div(the_end - start, 20)

    ew_grouped =
      ew_times
      |> Enum.reduce(%{}, fn %{
                               action: action,
                               persona: persona,
                               key: key,
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
        buckets = buckets |> put_elem(bucket, elem(buckets, bucket) + 1)

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

    socket = socket |> assign(:the_table, unique_ews)
    {:ok, socket}
  end

  defp normalize(list) do
    max = Enum.max(list)
    list |> Enum.map(fn i -> i / max end)
  end
end
