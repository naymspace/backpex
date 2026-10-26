defmodule Backpex.Integration.FieldMatrixTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [form: 2, put_submitter: 2, render_submit: 2]

  alias Backpex.Test.Sample

  # One entry per field module of Backpex. `Backpex.Test.SampleLive` has a field of every scalar type; the relation
  # fields are covered by the LiveResource that has one. Every entry runs the same tests, so a new field type only needs
  # an entry here to be rendered and saved in every view.
  #
  # - `:input` is how a user sets the field in a new form: `{:fill_in, label, value}`, `{:select, label, option}` or
  #   `{:check, labels}`. A field whose value a hook sets in a hidden input, which phoenix_test can't fill in, has
  #   `{:hidden, params}` with the form params that the hook would set,
  # - `:stored` is the value of `:column` after saving that input,
  # - `:shown` is the text the index and show views render for that value.
  @scalar_fields [
    {Backpex.Fields.Text, column: :text, input: {:fill_in, "Text", "Hello"}, stored: "Hello", shown: "Hello"},
    {Backpex.Fields.Textarea,
     column: :textarea, input: {:fill_in, "Textarea", "Some text"}, stored: "Some text", shown: "Some text"},
    {Backpex.Fields.Number, column: :number, input: {:fill_in, "Number", "42"}, stored: 42, shown: "42"},
    {Backpex.Fields.Boolean, column: :boolean, input: {:check, ["Boolean"]}, stored: true, shown: nil},
    {Backpex.Fields.Select, column: :select, input: {:select, "Select", "Two"}, stored: :two, shown: "Two"},
    {Backpex.Fields.MultiSelect,
     column: :multi_select, input: {:check, ["Red", "Blue"]}, stored: ["red", "blue"], shown: "Red"},
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

  # Fields that need a relation or an upload. They are rendered in every view of their LiveResource; saving them is
  # covered by the tests of each field in `integration_test/fields`.
  @relation_fields [
    {Backpex.Fields.BelongsTo, path: "/admin/samples", factory: :sample, field: :category},
    {Backpex.Fields.Upload, path: "/admin/samples", factory: :sample, field: :upload},
    {Backpex.Fields.HasMany, path: "/admin/posts", factory: :post, field: :tags},
    {Backpex.Fields.HasManyThrough, path: "/admin/users", factory: :user, field: :addresses},
    {Backpex.Fields.InlineCRUD, path: "/admin/users", factory: :user, field: :social_links}
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

        index = conn |> visit(~p"/admin/samples") |> assert_has("table tbody tr", count: 1)
        show = conn |> visit(~p"/admin/samples/#{sample.id}/show") |> assert_has("dl")

        if shown = @opts[:shown] do
          assert_has(index, "table tbody td", text: shown)
          assert_has(show, "dd", text: shown)
        end
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
    @opts opts
    describe inspect(module) do
      test "renders in the index, show, new and edit views", %{conn: conn} do
        item = insert(@opts[:factory])
        path = @opts[:path]

        conn |> visit(path) |> assert_has("table tbody tr", count: 1)
        conn |> visit("#{path}/#{item.id}/show") |> assert_has("dl")
        conn |> visit("#{path}/new") |> assert_has("#resource-form")
        conn |> visit("#{path}/#{item.id}/edit") |> assert_has("#resource-form")
      end
    end
  end

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
