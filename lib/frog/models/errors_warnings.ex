defmodule Frog.ErrorsWarnings do
  use Ecto.Schema

  @primary_key false
  schema "errors_warnings" do
    field :event_id, :string
    field :epoch, :integer
    field :persona, :string
    field :action, :string
    field :the_request, :string
    field :type, :string
    field :key, :string
    field :cnt, :integer
    field :item, :string
  end
end
