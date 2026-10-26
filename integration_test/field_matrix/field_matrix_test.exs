defmodule Backpex.Integration.FieldMatrixTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [form: 2, put_submitter: 2, render_submit: 2]

  alias Backpex.Test.Sample
  alias Backpex.Test.SampleLive
  alias Backpex.Test.UsersAddresses

  # One entry per field module of Backpex. `Backpex.Test.SampleLive` has a field of every scalar type; the relation
  # fields are covered by the LiveResource that has one. Every entry runs the same tests, so a new field type only needs
  # an entry here to be rendered and saved in every view.
  #
  # - `:input` is how a user sets the field in a new form: `{:fill_in, label, value}`, `{:select, label, option}` or
  #   `{:check, labels}`. A field whose value a hook sets in a hidden input, which phoenix_test can't fill in, has
  #   `{:hidden, params}` with the form params that the hook would set,
  # - `:stored` is the value of `:column` after saving that input,
  # - `:shown` is what the index and show views render for that value in the field's cell: the exact text of the cell,
  #   `{:selector, css}` for an element in it or `{:selector, css, text}` for an element with that exact text. A list
  #   holds several of these.
  @scalar_fields [
    {Backpex.Fields.Text, column: :text, input: {:fill_in, "Text", "Hello"}, stored: "Hello", shown: "Hello"},
    {Backpex.Fields.Textarea,
     column: :textarea, input: {:fill_in, "Textarea", "Some text"}, stored: "Some text", shown: "Some text"},
    {Backpex.Fields.Number, column: :number, input: {:fill_in, "Number", "42"}, stored: 42, shown: "42"},
    {Backpex.Fields.Boolean,
     column: :boolean, input: {:check, ["Boolean"]}, stored: true, shown: {:selector, ".hero-check-solid"}},
    {Backpex.Fields.Select, column: :select, input: {:select, "Select", "Two"}, stored: :two, shown: "Two"},
    {Backpex.Fields.MultiSelect,
     column: :multi_select,
     input: {:check, ["Red", "Blue"]},
     stored: ["red", "blue"],
     shown: [{:selector, ".badge", "Red"}, {:selector, ".badge", "Blue"}]},
    {Backpex.Fields.Checkgroup,
     column: :checkgroup, input: {:check, ["Read", "Write"]}, stored: ["read", "write"], shown: "Read, Write"},
    {Backpex.Fields.Date,
     column: :date, input: {:fill_in, "Date", "2026-10-26"}, stored: ~D[2026-10-26], shown: "2026-10-26"},
    {Backpex.Fields.DateTime,
     column: :date_time,
     input: {:fill_in, "Date Time", "2026-10-26T14:30"},
     stored: ~U[2026-10-26 14:30:00Z],
     shown: "2026-10-26 02:30 PM"},
    {Backpex.Fields.Time, column: :time, input: {:fill_in, "Time", "14:30"}, stored: ~T[14:30:00], shown: "02:30 PM"},
    {Backpex.Fields.Email,
     column: :email,
     input: {:fill_in, "Email", "jane@example.com"},
     stored: "jane@example.com",
     shown: "jane@example.com"},
    {Backpex.Fields.URL,
     column: :url,
     input: {:fill_in, "URL", "https://example.com"},
     stored: "https://example.com",
     shown: "https://example.com"},
    {Backpex.Fields.Currency,
     column: :currency, input: {:hidden, %{currency: "12.50"}}, stored: Money.new(1250), shown: "$12.50"}
  ]

  # Fields that need a relation or an upload. `insert_item/1` inserts an item of `:path` with a value for the field.
  # `:index`, `:show`, `:new` and `:edit` list the `{selector, opts}` assertions of each view for that field; the index
  # has none for fields that it doesn't show. Saving them is covered by the tests of each field in
  # `integration_test/fields`.
  @relation_fields [
    {Backpex.Fields.BelongsTo,
     path: "/admin/samples",
     index: [{"td a", text: "Science", exact: true}],
     show: [{"dt", text: "Category", exact: true}, {"dd a", text: "Science", exact: true}],
     new: [{"select", label: "Category"}],
     edit: [{"select", label: "Category", selected: "Science"}]},
    {Backpex.Fields.Upload,
     path: "/admin/samples",
     index: [{"td p", text: "notes.txt", exact: true}],
     show: [{"dt", text: "Upload", exact: true}, {"dd p", text: "notes.txt", exact: true}],
     new: [{"input[type='file']", label: "Upload"}],
     edit: [{"input[type='file']", label: "Upload"}, {"button[aria-label='Remove notes.txt']", []}]},
    {Backpex.Fields.HasMany,
     path: "/admin/posts",
     index: [{"td a", text: "Elixir", exact: true}, {"td a", text: "Phoenix", exact: true}],
     show: [
       {"dt", text: "Tags", exact: true},
       {"dd a", text: "Elixir", exact: true},
       {"dd a", text: "Phoenix", exact: true}
     ],
     new: [{"#resource-form_tags-label", text: "Tags", exact: true}],
     edit: [
       {"#has-many-tags label:has(input[checked])", text: "Elixir", exact: true},
       {"#has-many-tags label:has(input[checked])", text: "Phoenix", exact: true}
     ]},
    {Backpex.Fields.HasManyThrough,
     path: "/admin/users",
     index: [],
     show: [
       {"dt", text: "Addresses", exact: true},
       {"dd td", text: "Main Street 1", exact: true},
       {"dd td", text: "Billing", exact: true}
     ],
     new: [{"#has-many-through-label-addresses", text: "Addresses", exact: true}],
     edit: [
       {"table[aria-labelledby='has-many-through-label-addresses'] td", text: "Main Street 1", exact: true},
       {"table[aria-labelledby='has-many-through-label-addresses'] td", text: "Billing", exact: true}
     ]},
    {Backpex.Fields.InlineCRUD,
     path: "/admin/users",
     index: [],
     show: [
       {"dt", text: "Social links", exact: true},
       {"dd td", text: "Mastodon", exact: true},
       {"dd td", text: "https://mastodon.example/@jane", exact: true}
     ],
     new: [{"#inline-crud-label-social_links", text: "Social links", exact: true}],
     edit: [
       {"input[name='change[social_links][0][label]'][value='Mastodon']", []},
       {"input[name='change[social_links][0][url]'][value='https://mastodon.example/@jane']", []}
     ]}
  ]

  @field_modules Enum.map(@scalar_fields ++ @relation_fields, &elem(&1, 0))

  test "covers every field module of Backpex" do
    {:ok, modules} = :application.get_key(:backpex, :modules)

    field_modules =
      Enum.filter(modules, fn module ->
        Code.ensure_loaded!(module)
        Backpex.Field in (module.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten())
      end)

    assert Enum.sort(field_modules) == Enum.sort(@field_modules)
  end

  for {module, opts} <- @scalar_fields do
    @opts opts
    describe inspect(module) do
      test "saves a value from the new form", %{conn: conn} do
        session = visit(conn, ~p"/admin/samples/new")
        session = if @opts[:column] == :text, do: session, else: fill_in(session, "Text", with: "Sample")

        set_field_and_save(session, @opts[:input])

        assert [sample] = Repo.all(Sample)
        assert Map.fetch!(sample, @opts[:column]) == @opts[:stored]
      end

      test "renders the value on the index and show views", %{conn: conn} do
        sample = insert(:sample, [{@opts[:column], @opts[:stored]}])

        conn
        |> visit(~p"/admin/samples")
        |> assert_has("table tbody tr", count: 1)
        |> assert_shown(:index, @opts[:column], @opts[:shown])

        conn
        |> visit(~p"/admin/samples/#{sample.id}/show")
        |> assert_shown(:show, @opts[:column], @opts[:shown])
      end

      test "keeps the value when another field of the edit form changes", %{conn: conn} do
        sample = insert(:sample, [{@opts[:column], @opts[:stored]}])

        {other_column, other_label, other_param, other_value} =
          if @opts[:column] == :number, do: {:text, "Text", "Changed", "Changed"}, else: {:number, "Number", "7", 7}

        conn
        |> visit(~p"/admin/samples/#{sample.id}/edit")
        |> fill_in(other_label, with: other_param)
        |> click_button("Save")

        updated = Repo.get!(Sample, sample.id)
        assert Map.fetch!(updated, other_column) == other_value
        assert Map.fetch!(updated, @opts[:column]) == @opts[:stored]
      end
    end
  end

  for {module, opts} <- @relation_fields do
    @module module
    @opts opts
    describe inspect(module) do
      test "renders in the index, show, new and edit views", %{conn: conn} do
        item = insert_item(@module)
        path = @opts[:path]

        conn |> visit(path) |> assert_has("table tbody tr", count: 1) |> assert_all(@opts[:index])
        conn |> visit("#{path}/#{item.id}/show") |> assert_all(@opts[:show])
        conn |> visit("#{path}/new") |> within("#resource-form", &assert_all(&1, @opts[:new]))
        conn |> visit("#{path}/#{item.id}/edit") |> within("#resource-form", &assert_all(&1, @opts[:edit]))
      end
    end
  end

  defp insert_item(Backpex.Fields.BelongsTo), do: insert(:sample, category: build(:category, name: "Science"))
  defp insert_item(Backpex.Fields.Upload), do: insert(:sample, upload: "notes.txt")

  defp insert_item(Backpex.Fields.HasMany),
    do: insert(:post, tags: [build(:tag, name: "Elixir"), build(:tag, name: "Phoenix")])

  defp insert_item(Backpex.Fields.HasManyThrough) do
    address = build(:address, street: "Main Street 1")
    insert(:user, users_addresses: [%UsersAddresses{address: address, type: :billing}])
  end

  defp insert_item(Backpex.Fields.InlineCRUD),
    do: insert(:user, social_links: [%{label: "Mastodon", url: "https://mastodon.example/@jane"}])

  defp assert_all(session, assertions) do
    Enum.reduce(assertions, session, fn {selector, opts}, session -> assert_has(session, selector, opts) end)
  end

  # The index and show views render the fields of `Backpex.Test.SampleLive` in the order of `fields/0`: one table column
  # after the selection checkbox and one `dl` in its own `div` per field. The label assertions make sure that the
  # selectors point at the field.
  defp assert_shown(session, :index, column, shown) do
    position = field_position(column) + 1

    session
    |> assert_has("table thead th:nth-child(#{position})", text: field_label(column), exact: true)
    |> assert_shown_in("table tbody td:nth-child(#{position})", shown)
  end

  defp assert_shown(session, :show, column, shown) do
    container = "div:nth-child(#{field_position(column)}) > dl"

    session
    |> assert_has("#{container} > dt", text: field_label(column), exact: true)
    |> assert_shown_in("#{container} > dd", shown)
  end

  defp assert_shown_in(session, cell, shown) when is_list(shown),
    do: Enum.reduce(shown, session, &assert_shown_in(&2, cell, &1))

  defp assert_shown_in(session, cell, {:selector, css}), do: assert_has(session, "#{cell} #{css}")

  defp assert_shown_in(session, cell, {:selector, css, text}),
    do: assert_has(session, "#{cell} #{css}", text: text, exact: true)

  defp assert_shown_in(session, cell, text), do: assert_has(session, cell, text: text, exact: true)

  defp field_position(column),
    do: SampleLive.fields() |> Keyword.keys() |> Enum.find_index(&(&1 == column)) |> Kernel.+(1)

  defp field_label(column), do: SampleLive.fields() |> Keyword.fetch!(column) |> Map.fetch!(:label)

  # The params of a hidden input that a hook fills in are sent as values of the submit.
  defp set_field_and_save(session, {:hidden, params}) do
    unwrap(session, fn view ->
      view
      |> form("#resource-form")
      |> put_submitter("button[value=save]")
      |> render_submit(%{change: params})
    end)
  end

  defp set_field_and_save(session, input), do: session |> set_field(input) |> click_button("Save")

  defp set_field(session, {:fill_in, label, value}), do: fill_in(session, label, with: value)
  defp set_field(session, {:select, label, option}), do: select(session, label, option: option)
  defp set_field(session, {:check, labels}), do: Enum.reduce(labels, session, &check(&2, &1))
end
