defmodule Backpex.Fields.HasManyTest do
  use Demo.DataCase, async: false

  import Demo.EctoFactory

  alias Backpex.Fields.HasMany
  alias Demo.Post
  alias Phoenix.LiveView.Socket

  setup do
    tags = Map.new(~w[elixir erlang rust], &{&1, insert(:tag, name: &1)})

    %{tags: tags}
  end

  describe "options depending on the form" do
    test "are loaded again when the options query changes" do
      socket = update_field(%Socket{}, form(%Post{tags: []}, "e"))

      assert option_labels(socket) == ~w[elixir erlang]
      assert socket.assigns.options_count == 2

      socket = update_field(socket, form(%Post{tags: []}, "r"))

      assert option_labels(socket) == ~w[rust]
      assert socket.assigns.options_count == 1
    end

    test "are not loaded again while the options query stays the same" do
      socket = update_field(%Socket{}, form(%Post{tags: []}, "e"))

      assert count_tag_queries(fn -> update_field(socket, form(%Post{tags: []}, "e", "Changed body")) end) == 0
      assert count_tag_queries(fn -> update_field(socket, form(%Post{tags: []}, "r")) end) > 0
    end

    test "deselect items that are no longer options", %{tags: tags} do
      post = %Post{tags: [tags["elixir"]]}

      socket = update_field(%Socket{}, form(post, "e"))

      assert socket.assigns.selected_ids == [tags["elixir"].id]

      socket = update_field(socket, form(post, "r"))

      assert socket.assigns.selected == []
      assert socket.assigns.selected_ids == []
    end

    test "select all only selects the options" do
      changeset =
        %Post{tags: []}
        |> Ecto.Changeset.change()
        |> HasMany.before_changeset(%{"tags_select_all" => ""}, [], Demo.Repo, field(), %{
          form: form(%Post{tags: []}, "r")
        })

      assert for(%{action: :update, data: tag} <- changeset.changes.tags, do: tag.name) == ["rust"]
    end
  end

  defp field do
    {:tags,
     %{
       module: HasMany,
       label: "Tags",
       display_field: :name,
       live_resource: DemoWeb.TagLive,
       query_limit: 10,
       options_query: fn query, assigns ->
         prefix = Phoenix.HTML.Form.input_value(assigns.form, :title) || ""

         query
         |> where([tag], like(tag.name, ^"#{prefix}%"))
         |> order_by([tag], tag.name)
       end
     }}
  end

  defp form(post, title, body \\ "Body") do
    post
    |> Ecto.Changeset.cast(%{"title" => title, "body" => body}, [:title, :body])
    |> Phoenix.Component.to_form(as: :change)
  end

  defp update_field(socket, form) do
    {_name, field_options} = field = field()

    assigns = %{
      type: :form,
      name: :tags,
      field: field,
      field_options: field_options,
      live_resource: DemoWeb.PostLive,
      form: form
    }

    {:ok, socket} = HasMany.update(assigns, socket)
    socket
  end

  defp option_labels(socket), do: Enum.map(socket.assigns.options, fn {label, _id} -> label end)

  defp count_tag_queries(fun) do
    ref = make_ref()
    handler_id = {__MODULE__, ref}
    :telemetry.attach(handler_id, [:demo, :repo, :query], &__MODULE__.handle_query/4, {self(), ref})

    try do
      fun.()
    after
      :telemetry.detach(handler_id)
    end

    receive_tag_queries(ref, 0)
  end

  @doc false
  def handle_query(_event, _measurements, %{source: "tags"}, {test_pid, ref}) do
    if self() == test_pid, do: send(test_pid, {ref, :query})
  end

  def handle_query(_event, _measurements, _metadata, _config), do: :ok

  defp receive_tag_queries(ref, count) do
    receive do
      {^ref, :query} -> receive_tag_queries(ref, count + 1)
    after
      0 -> count
    end
  end
end
