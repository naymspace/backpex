defmodule Backpex.Integration.Fields.HasManyTest do
  use Backpex.ConnCase, async: true

  import Ecto.Query

  alias Backpex.Fields.HasMany
  alias Backpex.Test.Post
  alias Backpex.Test.PostLive
  alias Backpex.Test.ShortLink
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveViewTest

  require Phoenix.LiveViewTest

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

      assert count_queries("tags", fn -> update_field(socket, form(%Post{tags: []}, "e", "Changed body")) end) == 0
      assert count_queries("tags", fn -> update_field(socket, form(%Post{tags: []}, "r")) end) > 0
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
        |> HasMany.before_changeset(%{"tags_select_all" => ""}, [], field(), %{
          form: form(%Post{tags: []}, "r"),
          live_resource: PostLive
        })

      assert for(%{action: :update, data: tag} <- changeset.changes.tags, do: tag.name) == ["rust"]
    end
  end

  # `Backpex.Test.ProductShortLinksLive` has a HasMany field of `Backpex.Test.ShortLink`, whose key is `short_key`.
  describe "a related schema whose key is not id" do
    setup do
      # The keys come from the factory's sequence: equal keys would make concurrent tests wait for each other.
      product = insert(:product, short_links: [build(:short_link, url: "https://docs.example.com/")])
      other_link = insert(:short_link, url: "https://blog.example.com/")

      %{product: product, link: hd(product.short_links), other_link: other_link}
    end

    test "renders the keys as option values and selects the current ones", context do
      %{conn: conn, product: product, link: link, other_link: other_link} = context

      conn
      |> visit(~p"/admin/product-short-links/#{product.id}/edit")
      |> assert_has("#has-many-short_links input[type=checkbox][value='#{link.short_key}'][checked]")
      |> assert_has("#has-many-short_links input[type=checkbox][value='#{other_link.short_key}']:not([checked])")
      |> assert_has("#has-many-short_links .badge span", text: "https://docs.example.com/", exact: true)
      |> refute_has("#has-many-short_links .badge span", text: "https://blog.example.com/")
    end

    test "selects a current item that is not among the loaded options", context do
      %{product: product, link: link, other_link: other_link} = context

      field_options = %{
        module: HasMany,
        label: "Short Links",
        display_field: :url,
        live_resource: Backpex.Test.ShortLinkLive,
        query_limit: 1,
        options_query: fn query, _assigns ->
          query |> where([link], like(link.url, "https://%.example.com/")) |> order_by([link], link.url)
        end
      }

      assigns = %{
        type: :form,
        name: :short_links,
        field: {:short_links, field_options},
        field_options: field_options,
        live_resource: Backpex.Test.ProductShortLinksLive,
        form: product |> Ecto.Changeset.change() |> Phoenix.Component.to_form(as: :change)
      }

      {:ok, socket} = HasMany.update(assigns, %Socket{})

      assert socket.assigns.options == [{"https://blog.example.com/", other_link.short_key}]
      assert socket.assigns.selected == [{"https://docs.example.com/", link.short_key}]
    end

    test "saves a changed selection", %{conn: conn, product: product, other_link: other_link} do
      {:ok, view, _html} = LiveViewTest.live(conn, ~p"/admin/product-short-links/#{product.id}/edit")
      form = LiveViewTest.form(view, "#resource-form", change: %{short_links: ["", other_link.short_key]})

      html = LiveViewTest.render_change(form, %{"_target" => ["change", "short_links"]})
      badges = html |> LazyHTML.from_fragment() |> LazyHTML.query(".badge span")
      assert LazyHTML.text(badges) == "https://blog.example.com/"

      LiveViewTest.render_submit(form, %{"save-type" => "save"})
      LiveViewTest.assert_redirect(view, ~p"/admin/product-short-links")

      short_keys = from(link in ShortLink, where: link.product_id == ^product.id, select: link.short_key)
      assert Repo.all(short_keys) == [other_link.short_key]
    end
  end

  defp field do
    {:tags,
     %{
       module: HasMany,
       label: "Tags",
       display_field: :name,
       live_resource: Backpex.Test.TagLive,
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
      live_resource: PostLive,
      form: form
    }

    {:ok, socket} = HasMany.update(assigns, socket)
    socket
  end

  defp option_labels(socket), do: Enum.map(socket.assigns.options, fn {label, _id} -> label end)
end
