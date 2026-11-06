defmodule Backpex.Test.AdapterConformance do
  @moduledoc """
  The tests every `Backpex.Adapter` has to pass, run against the adapter of a LiveResource.

  They call the adapter callbacks with the queries (see `Backpex.Query`) and assigns the views of Backpex build, so an
  adapter that passes them works with the index, show and form views. Use it in a test module that defines `insert_item/1`, which stores an
  item with the given attributes, and `new_item/0`, which returns an unsaved item:

      defmodule Backpex.Integration.Adapters.EctoAdapterTest do
        use Backpex.DataCase, async: true
        use Backpex.Test.AdapterConformance, live_resource: Backpex.Test.TagLive, field: :name

        def insert_item(attrs), do: insert(:tag, attrs)
        def new_item, do: %Backpex.Test.Tag{}
      end

  `field` is a searchable and orderable text field of the LiveResource that its changesets accept. The tests set it to
  values that sort and match differently. `attrs` are the other form params a new item needs.

  The adapter callbacks are still changing (see `Backpex.Adapter`), so the suite lives in the tests of Backpex for now.
  Once the callbacks are stable, it can become public for adapters outside of Backpex.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      import Backpex.Test.AdapterConformance

      @live_resource Keyword.fetch!(opts, :live_resource)
      @field Keyword.fetch!(opts, :field)
      @attrs Keyword.get(opts, :attrs, %{})

      describe "#{inspect(@live_resource)} adapter read/1 of one item" do
        test "returns the item with the primary value" do
          item = insert_item(%{@field => "Alpha"})

          assert [found] = read_item(@live_resource, Backpex.LiveResource.primary_value(item, @live_resource))
          assert Map.fetch!(found, @field) == "Alpha"
        end

        test "returns no item for an unknown primary value" do
          item = insert_item(%{@field => "Alpha"})
          primary_value = Backpex.LiveResource.primary_value(item, @live_resource)
          adapter(@live_resource).delete_all([item], @live_resource)

          assert read_item(@live_resource, primary_value) == []
        end
      end

      describe "#{inspect(@live_resource)} adapter read/1, count/1 and aggregate/1" do
        setup do
          for value <- ~w(Bravo Alpha Charlie), do: insert_item(%{@field => value})
          :ok
        end

        test "order by a field in both directions" do
          assert list_values(@live_resource, @field, order_by: @field, order_direction: :asc) == ~w(Alpha Bravo Charlie)

          assert list_values(@live_resource, @field, order_by: @field, order_direction: :desc) ==
                   ~w(Charlie Bravo Alpha)
        end

        test "return a page of the ordered items" do
          assert list_values(@live_resource, @field, order_by: @field, order_direction: :asc, page: 1, per_page: 2) ==
                   ~w(Alpha Bravo)

          assert list_values(@live_resource, @field, order_by: @field, order_direction: :asc, page: 2, per_page: 2) ==
                   ~w(Charlie)
        end

        test "search case-insensitively for a part of a searchable field" do
          assert list_values(@live_resource, @field, order_by: @field, order_direction: :asc, search: "aLP") ==
                   ~w(Alpha)

          assert list_values(@live_resource, @field, order_by: @field, order_direction: :asc, search: "nothing") == []
        end

        test "count the items that match the search" do
          assert count(@live_resource, []) == 3
          assert count(@live_resource, search: "a") == 3
          assert count(@live_resource, search: "rav") == 1
        end

        test "aggregate the items that match the search and the where expression of each aggregate" do
          query =
            @live_resource
            |> assigns(search: "a")
            |> Backpex.LiveResource.index_query()
            |> Backpex.Query.unset([:sort, :default_sort, :limit, :offset, :load])
            |> Backpex.Query.aggregate(:total, :count)
            |> Backpex.Query.aggregate(:first, {:min, @field})
            |> Backpex.Query.aggregate(:bravos, :count, where: [{@field, "Bravo"}])

          assert adapter(@live_resource).aggregate(query) == {:ok, %{total: 3, first: "Alpha", bravos: 1}}
        end
      end

      describe "#{inspect(@live_resource)} adapter change/6, insert/2 and update/2" do
        test "insert a valid change" do
          changeset = change(@live_resource, new_item(), Map.put(@attrs, to_string(@field), "Inserted"), :insert)

          assert {:ok, item} = adapter(@live_resource).insert(changeset, @live_resource)
          assert @live_resource |> reload(item) |> Map.fetch!(@field) == "Inserted"
        end

        test "update an item" do
          # The edit view changes the item as the adapter returns it for the fields of the view.
          item = reload(@live_resource, insert_item(%{@field => "Before"}), :edit)
          changeset = change(@live_resource, item, %{to_string(@field) => "After"}, :update)

          assert {:ok, _item} = adapter(@live_resource).update(changeset, @live_resource)
          assert @live_resource |> reload(item) |> Map.fetch!(@field) == "After"
        end

        test "refuse an invalid change" do
          changeset = change(@live_resource, new_item(), Map.put(@attrs, to_string(@field), ""), :insert)

          assert {:error, _changeset} = adapter(@live_resource).insert(changeset, @live_resource)
          assert count(@live_resource, []) == 0
        end
      end

      describe "#{inspect(@live_resource)} adapter delete_all/2" do
        test "delete the given items and keep the others" do
          [item, other_item, kept_item] = for value <- ~w(One Two Three), do: insert_item(%{@field => value})

          assert {:ok, deleted} = adapter(@live_resource).delete_all([item, other_item], @live_resource)
          assert length(deleted) == 2

          assert list_values(@live_resource, @field, order_by: @field, order_direction: :asc) == [
                   Map.fetch!(kept_item, @field)
                 ]
        end
      end
    end
  end

  @doc "The adapter of the LiveResource."
  def adapter(live_resource), do: live_resource.config(:adapter)

  @doc "The assigns of the index view, as the views of Backpex pass them to the adapter."
  def assigns(live_resource, query_options \\ []) do
    assigns = %{live_resource: live_resource, live_action: :index, filters: [], filter_values: %{}}
    fields = Backpex.LiveResource.fields(live_resource, :index, assigns)

    query_options =
      Map.merge(
        %{order_by: nil, order_direction: :asc, page: 1, per_page: 15, search: ""},
        Map.new(query_options)
      )

    Map.merge(assigns, %{
      fields: fields,
      query_options: query_options,
      init_order: live_resource.config(:init_order) |> Backpex.LiveResource.resolve_init_order(assigns)
    })
  end

  @doc "Reads the items of the query the index view builds for `query_options` and returns the values of `field`."
  def list_values(live_resource, field, query_options) do
    query = live_resource |> assigns(query_options) |> Backpex.LiveResource.index_query()

    {:ok, items} = adapter(live_resource).read(query)

    Enum.map(items, &Map.fetch!(&1, field))
  end

  @doc "Counts the items like the index view, which passes the search and the filters, but no order or page."
  def count(live_resource, query_options) do
    query =
      live_resource
      |> assigns(query_options)
      |> Backpex.LiveResource.index_query()
      |> Backpex.Query.unset([:sort, :default_sort, :limit, :offset, :load])

    {:ok, count} = adapter(live_resource).count(query)

    count
  end

  @doc "Reads the item with the primary value like the show view, with the fields of `live_action`."
  def read_item(live_resource, primary_value, live_action \\ :show) do
    assigns = %{assigns(live_resource) | live_action: live_action}
    fields = Backpex.LiveResource.fields(live_resource, live_action, assigns)

    query =
      fields
      |> Backpex.Resource.items_query(assigns, live_resource)
      |> Backpex.Query.primary(primary_value)
      |> Backpex.Query.limit(1)

    {:ok, items} = adapter(live_resource).read(query)
    items
  end

  @doc "Builds the change of the form view for `attrs`."
  def change(live_resource, item, attrs, action) do
    live_action = if action == :insert, do: :new, else: :edit
    assigns = %{live_resource: live_resource, live_action: live_action}
    fields = Backpex.LiveResource.fields(live_resource, live_action, assigns)

    adapter(live_resource).change(item, attrs, fields, assigns, live_resource, action: action)
  end

  @doc "Reads the item again through the adapter, with the fields of `live_action`."
  def reload(live_resource, item, live_action \\ :index) do
    [item] = read_item(live_resource, Backpex.LiveResource.primary_value(item, live_resource), live_action)
    item
  end
end
