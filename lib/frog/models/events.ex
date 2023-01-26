defmodule Frog.Events do
  use Ecto.Schema

  @primary_key false
  schema "events" do
    field :id, :string
    field :epoch, :integer
    field :event, :string
  end
end
