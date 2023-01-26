defmodule Frog.Repo do
  use Ecto.Repo,
    otp_app: :frog,
    adapter: Ecto.Adapters.SQLite3
end
