defmodule Backpex.Integration.Adapters.EctoAdapterTest do
  @moduledoc """
  Runs the adapter conformance tests against `Backpex.Adapters.Ecto` and PostgreSQL, with a UUID, a string and an integer
  primary key.
  """

  defmodule UUIDPrimaryKey do
    use Backpex.DataCase, async: true
    use Backpex.Test.AdapterConformance, live_resource: Backpex.Test.TagLive, field: :name

    def insert_item(attrs), do: insert(:tag, attrs)
    def new_item, do: %Backpex.Test.Tag{}
  end

  defmodule StringPrimaryKey do
    use Backpex.DataCase, async: true

    use Backpex.Test.AdapterConformance,
      live_resource: Backpex.Test.ShortLinkLive,
      field: :url,
      attrs: %{"short_key" => "new-key"}

    def insert_item(attrs), do: insert(:short_link, attrs)
    def new_item, do: %Backpex.Test.ShortLink{}
  end

  defmodule IntegerPrimaryKey do
    use Backpex.DataCase, async: true
    use Backpex.Test.AdapterConformance, live_resource: Backpex.Test.NoteLive, field: :title

    def insert_item(attrs), do: insert(:note, attrs)
    def new_item, do: %Backpex.Test.Note{}
  end
end
