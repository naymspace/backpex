defmodule Backpex.Test.AdapterConformance do
  @moduledoc """
  The tests every `Backpex.Adapter` has to pass, run against the adapter of a LiveResource.

  They read with the queries (see `Backpex.Query`) and assigns the views of Backpex build, through `Backpex.Resource`
  like the views, so an adapter that passes them works with the index, show and form views. `Backpex.Resource` applies
  the parts of a query the adapter doesn't support in memory, see `c:Backpex.Adapter.supports?/2`. Use it in a test module that defines `insert_item/1`, which stores an
  item with the given attributes, and `new_item/0`, which returns an unsaved item:

      defmodule Backpex.Integration.Adapters.EctoAdapterTest do
        use Backpex.DataCase, async: true
        use Backpex.Test.AdapterConformance, live_resource: Backpex.Test.TagLive, field: :name

        def insert_item(attrs), do: insert(:tag, attrs)
        def new_item, do: %Backpex.Test.Tag{}
      end

  `field` is a searchable and orderable text field of the LiveResource that its changesets accept. The tests set it to
  values that sort and match differently. `attrs` are the other form params a new item needs. `nullable_field` is an
  integer field that may be `nil`. With it, the suite also checks filters, sorts and aggregates of a field with `nil`.

  The suite has no tests of relationships (paths and `exists/2` in expressions), as `Backpex.Adapters.Memory` has
  none. `Backpex.Integration.Adapters.QueryParityTest` covers them for `Backpex.Query.apply_to/2`.

  The adapter callbacks are still changing (see `Backpex.Adapter`), so the suite lives in the tests of Backpex for now.
  Once the callbacks are stable, it can become public for adapters outside of Backpex.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      import Backpex.Expr, only: [expr: 1]
      import Backpex.Test.AdapterConformance

      @live_resource Keyword.fetch!(opts, :live_resource)
      @field Keyword.fetch!(opts, :field)
      @attrs Keyword.get(opts, :attrs, %{})
      @nullable_field Keyword.get(opts, :nullable_field)

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

          assert Backpex.Resource.aggregate(query) == {:ok, %{total: 3, first: "Alpha", bravos: 1}}
        end
      end

      filter_tests()
      nil_tests()

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

  @doc "The tests of filters on the text field."
  defmacro filter_tests do
    quote do
      describe "#{inspect(@live_resource)} adapter read/1, count/1 and aggregate/1 with a filter" do
        setup do
          for value <- ["Bravo", "Alpha", "Charlie", "50%_off"], do: insert_item(%{@field => value})
          :ok
        end

        test "compare a field with every operator" do
          assert filtered_values(@live_resource, @field, expr(ref(^@field) == "Bravo")) == ~w(Bravo)
          assert filtered_values(@live_resource, @field, expr(ref(^@field) != "Bravo")) == ~w(50%_off Alpha Charlie)
          assert filtered_values(@live_resource, @field, expr(ref(^@field) < "Bravo")) == ~w(50%_off Alpha)
          assert filtered_values(@live_resource, @field, expr(ref(^@field) <= "Bravo")) == ~w(50%_off Alpha Bravo)
          assert filtered_values(@live_resource, @field, expr(ref(^@field) > "Bravo")) == ~w(Charlie)
          assert filtered_values(@live_resource, @field, expr(ref(^@field) >= "Bravo")) == ~w(Bravo Charlie)
          assert filtered_values(@live_resource, @field, expr("Bravo" < ref(^@field))) == ~w(Charlie)
          assert filtered_values(@live_resource, @field, [{@field, "Alpha"}]) == ~w(Alpha)
        end

        test "keep the items whose field is in a list, and none for an empty list" do
          assert filtered_values(@live_resource, @field, expr(ref(^@field) in ["Alpha", "Charlie", "Zulu"])) ==
                   ~w(Alpha Charlie)

          assert filtered_values(@live_resource, @field, expr(ref(^@field) not in ["Alpha", "Charlie"])) ==
                   ~w(50%_off Bravo)

          assert filtered_values(@live_resource, @field, expr(ref(^@field) in [])) == []

          assert filtered_values(@live_resource, @field, expr(ref(^@field) not in [])) ==
                   ~w(50%_off Alpha Bravo Charlie)
        end

        test "combine expressions with and, or and not" do
          assert filtered_values(@live_resource, @field, expr(ref(^@field) > "Alpha" and ref(^@field) < "Charlie")) ==
                   ~w(Bravo)

          assert filtered_values(@live_resource, @field, expr(ref(^@field) == "Alpha" or ref(^@field) == "Charlie")) ==
                   ~w(Alpha Charlie)

          assert filtered_values(
                   @live_resource,
                   @field,
                   expr(not (ref(^@field) == "Alpha" or ref(^@field) == "Charlie"))
                 ) == ~w(50%_off Bravo)

          assert filtered_values(@live_resource, @field, expr(is_nil(ref(^@field)))) == []

          assert filtered_values(@live_resource, @field, expr(not is_nil(ref(^@field)))) ==
                   ~w(50%_off Alpha Bravo Charlie)
        end

        test "match a part of a string, with or without the case and with % and _ as they are" do
          assert filtered_values(@live_resource, @field, expr(contains(ref(^@field), "ra"))) == ~w(Bravo)
          assert filtered_values(@live_resource, @field, expr(contains(ref(^@field), "RA"))) == []

          assert filtered_values(@live_resource, @field, expr(contains(ref(^@field), "RA", ignore_case: true))) ==
                   ~w(Bravo)

          assert filtered_values(@live_resource, @field, expr(starts_with(ref(^@field), "Al"))) == ~w(Alpha)
          assert filtered_values(@live_resource, @field, expr(starts_with(ref(^@field), "al"))) == []

          assert filtered_values(@live_resource, @field, expr(ends_with(ref(^@field), "LIE", ignore_case: true))) ==
                   ~w(Charlie)

          assert filtered_values(@live_resource, @field, expr(not ends_with(ref(^@field), "a"))) ==
                   ~w(50%_off Bravo Charlie)

          assert filtered_values(@live_resource, @field, expr(contains(ref(^@field), "%"))) == ~w(50%_off)
          assert filtered_values(@live_resource, @field, expr(contains(ref(^@field), "_"))) == ~w(50%_off)
          assert filtered_values(@live_resource, @field, expr(starts_with(ref(^@field), "50%_"))) == ~w(50%_off)
        end

        test "filter before searching, ordering and paginating" do
          filter = expr(ref(^@field) != "Charlie")

          first_page = [order_by: @field, order_direction: :desc, per_page: 2]

          assert filtered_values(@live_resource, @field, filter, first_page) == ~w(Bravo Alpha)

          assert filtered_values(@live_resource, @field, filter,
                   order_by: @field,
                   order_direction: :desc,
                   page: 2,
                   per_page: 2
                 ) == ~w(50%_off)

          assert filtered_values(@live_resource, @field, filter, search: "a") == ~w(Alpha Bravo)
        end

        test "count and aggregate the items of the filter" do
          query =
            @live_resource
            |> assigns()
            |> Backpex.LiveResource.index_query()
            |> Backpex.Query.unset([:sort, :default_sort, :limit, :offset, :load])
            |> Backpex.Query.filter(expr(ref(^@field) in ["Alpha", "Bravo", "Charlie"]))

          assert Backpex.Resource.count(query) == {:ok, 3}

          aggregated =
            query
            |> Backpex.Query.aggregate(:total, :count)
            |> Backpex.Query.aggregate(:last, {:max, @field})
            |> Backpex.Query.aggregate(:with_r, :count, where: expr(contains(ref(^@field), "r")))
            |> Backpex.Query.aggregate(:none, {:min, @field}, where: expr(ref(^@field) == "Zulu"))

          assert Backpex.Resource.aggregate(aggregated) == {:ok, %{total: 3, last: "Charlie", with_r: 2, none: nil}}
        end
      end
    end
  end

  @doc "The tests of filters, sorts and aggregates of the `nullable_field`, if the suite has one."
  defmacro nil_tests do
    quote do
      if @nullable_field do
        describe "#{inspect(@live_resource)} adapter read/1 and aggregate/1 of a field with nil" do
          setup do
            for {value, number} <- [{"Alpha", 2}, {"Bravo", nil}, {"Charlie", 1}, {"Delta", nil}, {"Echo", 2}] do
              insert_item(%{@field => value, @nullable_field => number})
            end

            :ok
          end

          test "keep an item with nil only with is_nil, not with a comparison or its negation" do
            assert filtered_values(@live_resource, @field, expr(is_nil(ref(^@nullable_field)))) == ~w(Bravo Delta)

            assert filtered_values(@live_resource, @field, expr(not is_nil(ref(^@nullable_field)))) ==
                     ~w(Alpha Charlie Echo)

            assert filtered_values(@live_resource, @field, expr(ref(^@nullable_field) == 2)) == ~w(Alpha Echo)
            assert filtered_values(@live_resource, @field, expr(ref(^@nullable_field) != 2)) == ~w(Charlie)
            assert filtered_values(@live_resource, @field, expr(not (ref(^@nullable_field) == 2))) == ~w(Charlie)
            assert filtered_values(@live_resource, @field, expr(ref(^@nullable_field) < 2)) == ~w(Charlie)
            assert filtered_values(@live_resource, @field, expr(ref(^@nullable_field) in [1, 3])) == ~w(Charlie)
            assert filtered_values(@live_resource, @field, expr(ref(^@nullable_field) not in [1, 3])) == ~w(Alpha Echo)

            assert filtered_values(
                     @live_resource,
                     @field,
                     expr(ref(^@nullable_field) != 2 or is_nil(ref(^@nullable_field)))
                   ) == ~w(Bravo Charlie Delta)

            # Unknown and false is false, unknown or true is true.
            assert filtered_values(
                     @live_resource,
                     @field,
                     expr(not (ref(^@nullable_field) == 2 and ref(^@field) == "Zulu"))
                   ) == ~w(Alpha Bravo Charlie Delta Echo)

            assert filtered_values(
                     @live_resource,
                     @field,
                     expr(ref(^@nullable_field) == 2 or ref(^@field) == "Bravo")
                   ) == ~w(Alpha Bravo Echo)
          end

          test "sort nil first or last as the direction says, then by the next sort" do
            sorted = fn direction, field_direction ->
              query =
                @live_resource
                |> assigns()
                |> Backpex.LiveResource.index_query()
                |> Backpex.Query.unset([:sort, :default_sort])
                |> Backpex.Query.sort([{@nullable_field, direction}, {@field, field_direction}])

              {:ok, items} = Backpex.Resource.read(query)

              Enum.map(items, &Map.fetch!(&1, @field))
            end

            assert sorted.(:asc_nulls_first, :asc) == ~w(Bravo Delta Charlie Alpha Echo)
            assert sorted.(:asc_nulls_last, :desc) == ~w(Charlie Echo Alpha Delta Bravo)
            assert sorted.(:desc_nulls_first, :asc) == ~w(Bravo Delta Alpha Echo Charlie)
            assert sorted.(:desc_nulls_last, :asc) == ~w(Alpha Echo Charlie Bravo Delta)
          end

          test "aggregate the values that are not nil" do
            query =
              @live_resource
              |> assigns()
              |> Backpex.LiveResource.index_query()
              |> Backpex.Query.unset([:sort, :default_sort, :limit, :offset, :load])
              |> Backpex.Query.aggregate(:items, :count)
              |> Backpex.Query.aggregate(:values, {:count, @nullable_field})
              |> Backpex.Query.aggregate(:sum, {:sum, @nullable_field})
              |> Backpex.Query.aggregate(:min, {:min, @nullable_field})
              |> Backpex.Query.aggregate(:max, {:max, @nullable_field})
              |> Backpex.Query.aggregate(:sum_of_nil, {:sum, @nullable_field},
                where: expr(is_nil(ref(^@nullable_field)))
              )

            assert Backpex.Resource.aggregate(query) ==
                     {:ok, %{items: 5, values: 3, sum: 5, min: 1, max: 2, sum_of_nil: nil}}
          end
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

    {:ok, items} = Backpex.Resource.read(query)

    Enum.map(items, &Map.fetch!(&1, field))
  end

  @doc """
  Reads the items of the query of the index view for `query_options` that match the expression, and returns their
  values of `field`, sorted by Elixir unless the `query_options` order them.
  """
  def filtered_values(live_resource, field, expression, query_options \\ []) do
    query =
      live_resource |> assigns(query_options) |> Backpex.LiveResource.index_query() |> Backpex.Query.filter(expression)

    {:ok, items} = Backpex.Resource.read(query)
    values = Enum.map(items, &Map.fetch!(&1, field))

    if Keyword.has_key?(query_options, :order_by), do: values, else: Enum.sort(values)
  end

  @doc "Counts the items like the index view, which passes the search and the filters, but no order or page."
  def count(live_resource, query_options) do
    query =
      live_resource
      |> assigns(query_options)
      |> Backpex.LiveResource.index_query()
      |> Backpex.Query.unset([:sort, :default_sort, :limit, :offset, :load])

    {:ok, count} = Backpex.Resource.count(query)

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

    {:ok, items} = Backpex.Resource.read(query)
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
