defmodule Backpex.Test.PostsTags do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "posts_tags" do
    belongs_to :post, Backpex.Test.Post, type: :binary_id
    belongs_to :tag, Backpex.Test.Tag, type: :binary_id

    timestamps()
  end
end
