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
    test "renders select all as a keyboard operable button that sends its name with a change event" do
      document = render_tags_form(all_selected: false)

      assert [button] = document |> LazyHTML.query("button[name]") |> Enum.to_list()
      assert LazyHTML.text(button) =~ "Select all"
      assert LazyHTML.attribute(button, "type") == ["button"]
      assert LazyHTML.attribute(button, "name") == ["change[tags_select_all]"]
      assert LazyHTML.attribute(button, "value") == [""]
      assert [phx_click] = LazyHTML.attribute(button, "phx-click")
      assert phx_click =~ ~s(["dispatch",{"event":"change"}])
    end

    test "renders deselect all when all options are selected" do
      document = render_tags_form(all_selected: true)

      assert [button] = document |> LazyHTML.query("button[name]") |> Enum.to_list()
      assert LazyHTML.text(button) =~ "Deselect all"
      assert LazyHTML.attribute(button, "name") == ["change[tags_deselect_all]"]
    end

    test "renders no select all button without options" do
      document = render_tags_form(options: [])

      assert document |> LazyHTML.query("button[name]") |> Enum.empty?()
      assert document |> LazyHTML.query("[data-part=empty]") |> LazyHTML.text() =~ "No options found"
    end

    test "renders a combobox that searches the options on the server" do
      document = render_tags_form(selected: [{"3", 3}], selected_ids: [3])
      root = LazyHTML.query(document, "#change_tags")

      assert LazyHTML.attribute(root, "phx-hook") == ["BackpexCombobox"]
      assert LazyHTML.attribute(root, "data-on-search") == ["search"]
      assert LazyHTML.attribute(root, "phx-target") == ["1"]
      assert document |> LazyHTML.query("[role=option]") |> LazyHTML.attribute("data-value") == ["1", "2"]

      # The selected item is on no loaded page of options, but it is shown and submitted.
      assert document |> LazyHTML.query("[data-part=badge-label]") |> LazyHTML.text() == "3"
      assert document |> LazyHTML.query(~s|input[name="change[tags][]"]|) |> LazyHTML.attribute("value") == ["3"]
    end

    test "renders show more below the options while there are more options to load" do
      refute render_tags_form(show_more: false) |> LazyHTML.query(~s|button[phx-click="show-more"]|) |> Enum.any?()

      button = render_tags_form(show_more: true) |> LazyHTML.query(~s|button[phx-click="show-more"]|)

      assert LazyHTML.text(button) =~ "Show more"
      assert LazyHTML.attribute(button, "type") == ["button"]
      assert LazyHTML.attribute(button, "phx-target") == ["1"]
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
          prompt: "Select options...",
          not_found_text: "No options found",
          options: [{"1", 1}, {"2", 2}],
          selected: [],
          selected_ids: [],
          all_selected: false,
          show_more: false,
          myself: %Phoenix.LiveComponent.CID{cid: 1}
        ],
        assigns
      )

    (&HasMany.render_form/1)
    |> render_component(assigns)
    |> LazyHTML.from_fragment()
  end
end
