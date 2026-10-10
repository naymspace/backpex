defmodule Backpex.Fields.HasManyTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Fields.HasMany

  defmodule Tag do
    @moduledoc false
    use Ecto.Schema

    schema "tags" do
      field :tenant_id, :integer
    end
  end

  defmodule Post do
    @moduledoc false
    use Ecto.Schema

    schema "posts" do
      many_to_many :tags, Backpex.Fields.HasManyTest.Tag, join_through: "posts_tags"
    end
  end

  defmodule TagsRepo do
    @moduledoc false
    def all(query) do
      send(self(), {:all, query})

      [Ecto.put_meta(%Tag{id: 1, tenant_id: 1}, state: :loaded)]
    end
  end

  defmodule TagLive do
    @moduledoc false
    def adapter_config(:schema), do: Tag
  end

  defmodule PostLive do
    @moduledoc false
    def config(:adapter), do: Backpex.Adapters.Ecto
    def adapter_config(:schema), do: Post
    def adapter_config(:repo), do: TagsRepo
  end

  describe "before_changeset/6" do
    test "selects all items of the options query" do
      options_query = fn query, assigns -> where(query, [tag], tag.tenant_id == ^assigns.tenant_id) end
      field = {:tags, %{module: HasMany, display_field: :id, live_resource: TagLive, options_query: options_query}}
      assigns = %{live_resource: PostLive, tenant_id: 1}

      changeset =
        %Post{}
        |> Ecto.Changeset.change()
        |> HasMany.before_changeset(%{"tags_select_all" => ""}, [], TagsRepo, field, assigns)

      assert_received {:all, %Ecto.Query{wheres: [%{params: [{1, _type}]}]}}
      assert [%Ecto.Changeset{data: %Tag{id: nil}}, %Ecto.Changeset{data: %Tag{id: 1}}] = changeset.changes.tags
    end
  end
end
