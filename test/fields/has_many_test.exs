defmodule Backpex.Fields.HasManyTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest, only: [render_component: 2]

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
    def translate({msg, _opts}), do: msg
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

  describe "render_form/1" do
    test "renders select all as a keyboard operable button that checks the hidden input" do
      document = render_tags_form(all_selected: false)

      assert [button] = document |> LazyHTML.query("button[type=button]") |> Enum.to_list()
      assert LazyHTML.text(button) =~ "Select all"
      assert [phx_click] = LazyHTML.attribute(button, "phx-click")
      assert phx_click =~ ~s("dispatch")
      assert phx_click =~ ~s("to":"#has-many-tags-toggle-all")

      assert ["change[tags_select_all]"] =
               document |> LazyHTML.query("#has-many-tags-toggle-all") |> LazyHTML.attribute("name")

      assert document |> LazyHTML.query("[role=button]:not([tabindex])") |> Enum.empty?()
    end

    test "renders deselect all when all options are selected" do
      document = render_tags_form(all_selected: true)

      assert document |> LazyHTML.query("button[type=button]") |> LazyHTML.text() =~ "Deselect all"

      assert ["change[tags_deselect_all]"] =
               document |> LazyHTML.query("#has-many-tags-toggle-all") |> LazyHTML.attribute("name")
    end
  end

  defp render_tags_form(assigns) do
    assigns =
      Keyword.merge(
        [
          name: :tags,
          field_options: %{module: HasMany, label: "Tags", display_field: :id, live_resource: TagLive},
          form: Phoenix.Component.to_form(%{}, as: :change),
          live_resource: PostLive,
          hide_label: false,
          readonly: false,
          errors: [],
          prompt: "Select options...",
          search_input: "",
          not_found_text: "No options found",
          options: [{"1", 1}, {"2", 2}],
          options_ids: [1, 2],
          selected: [],
          selected_ids: [],
          show_more: false,
          myself: %Phoenix.LiveComponent.CID{cid: 1}
        ],
        assigns
      )

    html = render_component(&HasMany.render_form/1, assigns)

    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#has-many-dropdown-tags-menu")
  end
end
