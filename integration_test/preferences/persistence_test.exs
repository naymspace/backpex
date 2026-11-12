defmodule Backpex.Integration.Preferences.PersistenceTest do
  @moduledoc """
  End-to-end coverage for the `persist: [:order, :filters, :columns]` option on `Backpex.LiveResource`. Mounts
  `Backpex.Test.PostLive` (configured with all three persistence kinds) and asserts that sort, filter, and column-toggle
  interactions emit a `push_event` with the expected preference key and value shape.

  The wire event name comes from `Backpex.Preferences.LiveView.event_name/0` and the keys come from
  `Backpex.Preferences.Keys.{order,filters,columns}/1`, so the test reflects the same contract the emitter uses.
  """
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Preferences.Keys, as: PrefKeys
  alias Backpex.Preferences.LiveView, as: PrefLiveView

  @resource_mod Backpex.Test.PostLive

  # assert_push_event expands to assert_receive, which pattern-matches the arguments. Bind the event name and key to
  # module-level constants or local variables before the macro call so the pattern is literal-shaped.
  @event_name PrefLiveView.event_name()

  # Where the default-filter redirect lands on a first visit: the `published` filter's default plus the canonical order
  # and pagination.
  @default_query_params %{
    "filters" => %{"published" => ["published"]},
    "order_by" => "id",
    "order_direction" => "asc",
    "page" => "1",
    "per_page" => "15"
  }

  describe "persist: [:order]" do
    test "sort change via column-header click emits push_event with order key", %{conn: conn} do
      insert(:post, title: "Alpha", published: true)
      insert(:post, title: "Beta", published: true)

      expected_key = PrefKeys.order(@resource_mod)

      conn
      |> visit(~p"/admin/posts?filters[published][]=published")
      # Clicking the Title column header sorts and routes through maybe_persist_order/2, which fires the push_event.
      |> click_link("Title")
      |> with_view(fn view ->
        assert_push_event(view, @event_name, %{
          key: ^expected_key,
          mirror: "session",
          value: %{"by" => "title", "direction" => "asc"}
        })
      end)
    end

    test "invalid persisted direction falls back to and repairs the initial order", %{conn: conn} do
      search = unique_search("persisted-order")

      posts =
        for title <- ["Cherry", "Apple", "Banana"] do
          insert(:post, title: "#{search}-#{title}", published: true)
        end

      first = Enum.min_by(posts, & &1.id)

      conn = put_persisted_order(conn, %{"by" => "title", "direction" => "error"})

      expected_key = PrefKeys.order(@resource_mod)

      conn
      |> visit(~p"/admin/posts?filters[published][]=published&search=#{search}")
      |> assert_has("table tbody tr:first-child td", text: first.title)
      |> with_view(fn view ->
        assert_push_event(view, @event_name, %{
          key: ^expected_key,
          mirror: "session",
          value: %{"by" => "id", "direction" => "asc"}
        })
      end)
    end

    test "persisted non-orderable field falls back to and repairs the initial order", %{conn: conn} do
      search = unique_search("persisted-order")

      posts =
        for title <- ["Cherry", "Apple", "Banana"] do
          insert(:post, title: "#{search}-#{title}", published: true)
        end

      first = Enum.min_by(posts, & &1.id)

      # `tags` is an existing field/atom, but PostLive marks it non-orderable.
      conn = put_persisted_order(conn, %{"by" => "tags", "direction" => "desc"})

      expected_key = PrefKeys.order(@resource_mod)

      conn
      |> visit(~p"/admin/posts?filters[published][]=published&search=#{search}")
      |> assert_has("table tbody tr:first-child td", text: first.title)
      |> with_view(fn view ->
        assert_push_event(view, @event_name, %{
          key: ^expected_key,
          mirror: "session",
          value: %{"by" => "id", "direction" => "asc"}
        })
      end)
    end

    test "valid persisted order remains the default for a clean URL", %{conn: conn} do
      search = unique_search("persisted-order")

      insert(:post, title: "#{search}-Cherry", published: true)
      insert(:post, title: "#{search}-Apple", published: true)
      insert(:post, title: "#{search}-Banana", published: true)

      conn = put_persisted_order(conn, %{"by" => "title", "direction" => "desc"})

      conn
      |> visit(~p"/admin/posts?filters[published][]=published&search=#{search}")
      |> assert_has("table tbody tr:first-child td", text: "#{search}-Cherry")
      |> assert_has("table tbody tr:last-child td", text: "#{search}-Apple")
    end

    test "a first visit with no order chosen writes nothing", %{conn: conn} do
      # The order on a first visit comes from the resource's own init_order, not from the user. Storing it would freeze
      # that default per user: the stored value wins over init_order from the next mount on, so a later change to the
      # resource's default would never reach them.
      search = unique_search("persisted-order")
      insert(:post, title: "#{search}-Alpha", published: true)

      conn
      |> visit(~p"/admin/posts?filters[published][]=published&search=#{search}")
      |> assert_has("table tbody tr:first-child td", text: "#{search}-Alpha")
      |> with_view(&refute_push_event(&1, @event_name, %{key: _key, value: %{"by" => _by, "direction" => _dir}}))
    end

    test "a first visit through the default-filter redirect writes nothing", %{conn: conn} do
      # The redirect canonicalizes order_by/order_direction into the URL, so the params carry an order on a plain first
      # visit — one nobody chose. This is the path a real first visit takes, and the URL is why it cannot be the signal
      # for "the user picked this".
      insert(:post, title: "Alpha", published: true)

      conn
      |> visit(~p"/admin/posts")
      |> assert_path(~p"/admin/posts", query_params: @default_query_params)
      |> with_view(&refute_push_event(&1, @event_name, %{key: _key, value: %{"by" => _by, "direction" => _dir}}))
    end

    test "an explicit URL order equal to the default writes nothing", %{conn: conn} do
      # Storing it would change no outcome — reading `nil` back yields the same order — and would cost the resource the
      # ability to keep choosing.
      search = unique_search("persisted-order")
      insert(:post, title: "#{search}-Alpha", published: true)

      conn
      |> visit(~p"/admin/posts?filters[published][]=published&order_by=id&order_direction=asc&search=#{search}")
      |> with_view(&refute_push_event(&1, @event_name, %{key: _key, value: %{"by" => _by, "direction" => _dir}}))
    end

    test "an explicit URL order that diverges from the default is written", %{conn: conn} do
      search = unique_search("persisted-order")
      insert(:post, title: "#{search}-Alpha", published: true)

      expected_key = PrefKeys.order(@resource_mod)

      conn
      |> visit(~p"/admin/posts?filters[published][]=published&order_by=title&order_direction=desc&search=#{search}")
      |> with_view(fn view ->
        assert_push_event(view, @event_name, %{key: ^expected_key, value: %{"by" => "title", "direction" => "desc"}})
      end)
    end

    test "explicit URL order takes precedence over valid persisted order", %{conn: conn} do
      search = unique_search("persisted-order")

      insert(:post, title: "#{search}-Popular", likes: 500, published: true)
      insert(:post, title: "#{search}-Average", likes: 50, published: true)
      insert(:post, title: "#{search}-New", likes: 1, published: true)

      conn = put_persisted_order(conn, %{"by" => "title", "direction" => "desc"})

      conn
      |> visit(~p"/admin/posts?filters[published][]=published&order_by=likes&order_direction=asc&search=#{search}")
      |> assert_has("table tbody tr:first-child td", text: "#{search}-New")
      |> assert_has("table tbody tr:last-child td", text: "#{search}-Popular")
    end
  end

  describe "persist: [:filters]" do
    test "filter change emits push_event with filters key", %{conn: conn} do
      insert(:post, title: "Published", published: true)
      insert(:post, title: "Draft", published: false)

      expected_key = PrefKeys.filters(@resource_mod)

      conn
      |> visit(~p"/admin/posts?filters[published][]=published")
      # Including not_published too routes through the change-filter handler → apply_filter_change/2 → push_event.
      |> check("Not published")
      |> with_view(fn view ->
        # The LiveResource emits several filter-persistence events over the mount + change cycle. We care that at least
        # one of them reflects the new two-value set and carries the filters key.
        assert_push_event(view, @event_name, %{
          key: ^expected_key,
          mirror: "session",
          value: %{"published" => ["published", "not_published"]}
        })
      end)
    end

    test "clear-filter emits push_event with empty map", %{conn: conn} do
      insert(:post, title: "Published", published: true)
      insert(:post, title: "Draft", published: false)

      expected_key = PrefKeys.filters(@resource_mod)

      conn
      |> visit(~p"/admin/posts?filters[published][]=published")
      # The URL collapses to no `filters[]` param, so the clear-filter handler itself must emit the empty-map
      # push_event — apply_index can't infer the cleared intent from the URL alone.
      #
      # Two buttons fire `clear-filter` for the same field (the inline "clear" link and the indicator badge's × icon).
      # Target the indicator by its accessible name.
      |> click_button("Clear Published? filter")
      |> with_view(fn view ->
        assert_push_event(view, @event_name, %{key: ^expected_key, mirror: "session", value: value})
        assert value == %{}
      end)
    end

    test "persisted %{} filters suppress redirect to defaults on mount", %{conn: conn} do
      # Simulates the round-trip after a user cleared every filter and navigated away: the preferences adapter holds an
      # explicit empty map. On return, `apply_index` must treat that state as "user cleared everything" and skip the
      # default-filter redirect. Without this, `maybe_redirect_to_default_filters` would see `query_options.filters ==
      # %{}` and re-apply the `:default` from the `published` filter, overwriting the user's persisted clear.
      search = unique_search("empty-filters")
      published_title = "#{search}-Published"
      draft_title = "#{search}-Draft"

      insert(:post, title: published_title, published: true)
      insert(:post, title: draft_title, published: false)

      conn = put_persisted_resource_preferences(conn, %{"filters" => %{}})

      conn
      |> visit(~p"/admin/posts?search=#{search}")
      # Both posts are visible → no `published` default was applied.
      |> assert_has("table tbody td", text: published_title)
      |> assert_has("table tbody td", text: draft_title)
    end

    test "no persisted filters still triggers redirect to defaults on mount", %{conn: conn} do
      # A fresh user with nothing in the preferences store still gets the `:default` filter applied (and the URL
      # rewritten to carry it).
      insert(:post, title: "Published Post", published: true)
      insert(:post, title: "Draft Post", published: false)

      conn
      |> visit(~p"/admin/posts")
      |> assert_path(~p"/admin/posts", query_params: @default_query_params)
    end
  end

  describe "persist: [:columns]" do
    test "column toggle emits push_event with columns key", %{conn: conn} do
      insert(:post, title: "Alpha", published: true)

      expected_key = PrefKeys.columns(@resource_mod)

      conn
      |> visit(~p"/admin/posts?filters[published][]=published")
      # maybe_push_columns/3 emits the push_event with the full active-fields map.
      |> uncheck("Title")
      |> with_view(fn view ->
        assert_push_event(view, @event_name, %{key: ^expected_key, value: value})

        # title was just toggled, so it must now be false; other fields remain true.
        assert is_map(value)
        assert value["title"] == false
      end)
    end
  end

  # `assert_push_event` and `refute_push_event` read the messages the LiveView sends the test process, so they need the
  # view itself.
  defp with_view(session, fun) do
    unwrap(session, fn view ->
      fun.(view)
      render(view)
    end)
  end

  defp unique_search(scope) do
    "#{scope}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp put_persisted_order(conn, order) do
    put_persisted_resource_preferences(conn, %{"order" => order})
  end

  defp put_persisted_resource_preferences(conn, preferences) do
    Plug.Test.init_test_session(conn, %{
      "backpex_preferences" => %{"resource" => %{inspect(@resource_mod) => preferences}}
    })
  end
end
