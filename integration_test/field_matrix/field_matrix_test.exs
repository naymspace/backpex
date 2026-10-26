defmodule Backpex.Integration.FieldMatrixTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.Sample

  # One entry per field module of Backpex. `Backpex.Test.SampleLive` has a field of every scalar type; the relation
  # fields are covered by the LiveResource that has one. Every entry runs the same tests, so a new field type only needs
  # an entry here to be rendered and saved in every view.
  #
  # - `:params` are the form params of a new item that set the field,
  # - `:stored` is the value of `:column` after saving these params,
  # - `:shown` is the text the index and show views render for that value,
  # - `:hidden` marks a field whose form value is set by a hook in a hidden input, which LiveViewTest can't fill in.
  @scalar_fields [
    {Backpex.Fields.Text, column: :text, params: %{text: "Hello"}, stored: "Hello", shown: "Hello"},
    {Backpex.Fields.Textarea,
     column: :textarea, params: %{textarea: "Some text"}, stored: "Some text", shown: "Some text"},
    {Backpex.Fields.Number, column: :number, params: %{number: "42"}, stored: 42, shown: "42"},
    {Backpex.Fields.Boolean, column: :boolean, params: %{boolean: "true"}, stored: true, shown: nil},
    {Backpex.Fields.Select, column: :select, params: %{select: "two"}, stored: :two, shown: "Two"},
    {Backpex.Fields.MultiSelect,
     column: :multi_select, params: %{multi_select: ["red", "blue"]}, stored: ["red", "blue"], shown: "Red"},
    {Backpex.Fields.Checkgroup,
     column: :checkgroup, params: %{checkgroup: ["read", "write"]}, stored: ["read", "write"], shown: "Read, Write"},
    {Backpex.Fields.Date, column: :date, params: %{date: "2026-10-26"}, stored: ~D[2026-10-26], shown: "2026-10-26"},
    {Backpex.Fields.DateTime,
     column: :date_time,
     params: %{date_time: "2026-10-26T14:30"},
     stored: ~U[2026-10-26 14:30:00Z],
     shown: "2026-10-26 02:30 PM"},
    {Backpex.Fields.Time, column: :time, params: %{time: "14:30"}, stored: ~T[14:30:00], shown: "02:30 PM"},
    {Backpex.Fields.Email,
     column: :email, params: %{email: "jane@example.com"}, stored: "jane@example.com", shown: "jane@example.com"},
    {Backpex.Fields.URL,
     column: :url, params: %{url: "https://example.com"}, stored: "https://example.com", shown: "https://example.com"},
    {Backpex.Fields.Currency,
     column: :currency, params: %{currency: "12.50"}, stored: Money.new(1250), shown: "$12.50", hidden: true}
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
        {:ok, view, _html} = live(conn, ~p"/admin/samples/new")
        params = Map.put_new(@opts[:params], :text, "Sample")
        {form_params, hidden_params} = if @opts[:hidden], do: Map.split(params, [:text]), else: {params, %{}}

        view
        |> form("#resource-form", change: form_params)
        |> put_submitter("button[value=save]")
        |> render_submit(%{change: hidden_params})

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
        {:ok, view, _html} = live(conn, ~p"/admin/samples/#{sample.id}/edit")

        {other_column, other_param, other_value} =
          if @opts[:column] == :number, do: {:text, "Changed", "Changed"}, else: {:number, "7", 7}

        view
        |> form("#resource-form", change: %{other_column => other_param})
        |> put_submitter("button[value=save]")
        |> render_submit()

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
end
