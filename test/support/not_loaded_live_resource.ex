defmodule Backpex.Test.NotLoadedLiveResource do
  @moduledoc """
  A LiveResource stand-in that tests unload to check that Backpex loads a LiveResource before looking at its callbacks.
  No other test uses it, so unloading it doesn't affect them or the coverage of Backpex.
  """

  defmodule Item do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "items" do
      field :quantity, :integer
    end
  end

  def config(:adapter), do: Backpex.Adapters.Ecto
  def adapter_config(:schema), do: Item
end
