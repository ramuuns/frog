defmodule Frog.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Frog.Repo,
      # Start the Telemetry supervisor
      FrogWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Frog.PubSub},
      # Start the Endpoint (http/https)
      FrogWeb.Endpoint,
      %{
        id: PhoenixEvents,
        start:
          {PhoenixEvents, :start_link,
           [
             %{
               persona: "frog",
               send_events: true,
               log_live_view: true,
               collector_host: Application.fetch_env!(:frog, :collector_host),
               collector_port: Application.fetch_env!(:frog, :collector_port),
               log_queries: true,
               queries_prefix: [:frog, :repo]
             },
             []
           ]}
      }
      # Start a worker by calling: Frog.Worker.start_link(arg)
      # {Frog.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Frog.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FrogWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
