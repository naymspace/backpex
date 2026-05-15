defmodule DemoWeb.Live.PreferencesPersistenceTest do
  @moduledoc """
  End-to-end coverage for the `persist: [:order, :filters, :columns]` option on
  `Backpex.LiveResource`. Mounts `DemoWeb.PostLive` (configured with all three
  persistence kinds) and asserts that sort, filter, and column-toggle
  interactions emit a `push_event` with the expected preference key and value
  shape.

  The wire event name comes from `Backpex.Preferences.LiveView.event_name/0`
  and the keys come from `Backpex.Preferences.Keys.{order,filters,columns}/1`,
  so the test reflects the same contract the emitter uses.
  """

  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  alias Backpex.Preferences.Keys, as: PrefKeys
  alias Backpex.Preferences.LiveView, as: PrefLiveView

  @resource_mod DemoWeb.PostLive

  # assert_push_event expands to assert_receive, which pattern-matches the
  # arguments. Bind the event name and key to module-level constants or local
  # variables before the macro call so the pattern is literal-shaped.
  @event_name PrefLiveView.event_name()

  describe "persist: [:order]" do
    test "sort change via column-header click emits push_event with order key", %{conn: conn} do
      insert(:post, title: "Alpha", published: true)
      insert(:post, title: "Beta", published: true)

      {:ok, view, _html} = live(conn, ~p"/admin/posts?filters[published][]=published")

      # Click the Title column header — triggers a sort and routes through
      # maybe_persist_order/2 which fires the push_event.
      view
      |> element("a", "Title")
      |> render_click()

      expected_key = PrefKeys.order(@resource_mod)

      assert_push_event(view, @event_name, %{
        key: ^expected_key,
        value: %{"by" => "title", "direction" => "asc"}
      })
    end
  end

  describe "persist: [:filters]" do
    test "filter change emits push_event with filters key", %{conn: conn} do
      insert(:post, title: "Published", published: true)
      insert(:post, title: "Draft", published: false)

      # Mount with the default published-only filter applied.
      {:ok, view, _html} = live(conn, ~p"/admin/posts?filters[published][]=published")

      # Toggle the filter to include not_published too — routes through
      # the change-filter handler → apply_filter_change/2 → push_event.
      view
      |> form("form[phx-change='change-filter']",
        filters: %{published: ["published", "not_published"]}
      )
      |> render_change()

      expected_key = PrefKeys.filters(@resource_mod)

      # The LiveResource emits several filter-persistence events over the mount
      # + change cycle. We care that at least one of them reflects the new
      # two-value set and carries the filters key.
      assert_push_event(view, @event_name, %{
        key: ^expected_key,
        value: %{"published" => ["published", "not_published"]}
      })
    end

    test "clear-filter emits push_event with empty map", %{conn: conn} do
      insert(:post, title: "Published", published: true)
      insert(:post, title: "Draft", published: false)

      # Mount with the default published-only filter applied.
      {:ok, view, _html} = live(conn, ~p"/admin/posts?filters[published][]=published")

      # Click the filter badge's clear (×) button for the `published` filter.
      # The URL collapses to no `filters[]` param, so the clear-filter handler
      # itself must emit the empty-map push_event — apply_index can't infer the
      # cleared intent from the URL alone.
      #
      # There are two buttons that fire `clear-filter` for the same field
      # (the inline "clear" link and the indicator badge's × icon). Target
      # the indicator explicitly via its aria-label.
      view
      |> element("button[aria-label='Clear Published? filter']")
      |> render_click()

      expected_key = PrefKeys.filters(@resource_mod)

      assert_push_event(view, @event_name, %{key: ^expected_key, value: value})
      assert value == %{}
    end

    test "persisted %{} filters suppress redirect to defaults on mount", %{conn: conn} do
      # Simulates the round-trip after a user cleared every filter and
      # navigated away: the preferences adapter holds an explicit empty map.
      # On return, `apply_index` must treat that state as "user cleared
      # everything" and skip the default-filter redirect. Without this,
      # `maybe_redirect_to_default_filters` would see `query_options.filters
      # == %{}` and re-apply the `:default` from the `published` filter,
      # overwriting the user's persisted clear.
      insert(:post, title: "Published Post", published: true)
      insert(:post, title: "Draft Post", published: false)

      session = %{
        "backpex_preferences" => %{
          "resource" => %{"DemoWeb.PostLive" => %{"filters" => %{}}}
        }
      }

      conn = Plug.Test.init_test_session(conn, session)

      {:ok, _view, html} = live(conn, ~p"/admin/posts")

      # Both posts are visible → no `published` default was applied.
      assert html =~ "Published Post"
      assert html =~ "Draft Post"
    end

    test "no persisted filters still triggers redirect to defaults on mount", %{conn: conn} do
      # Pins the existing onboarding flow: a fresh user with nothing in the
      # preferences store still gets the `:default` filter applied (and the
      # URL rewritten to carry it), so the bug fix doesn't regress this path.
      insert(:post, title: "Published Post", published: true)
      insert(:post, title: "Draft Post", published: false)

      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/admin/posts")
      assert to =~ "filters[published][]=published"
    end
  end

  describe "persist: [:columns]" do
    test "column toggle emits push_event with columns key", %{conn: conn} do
      insert(:post, title: "Alpha", published: true)

      {:ok, view, _html} = live(conn, ~p"/admin/posts?filters[published][]=published")

      # Toggle the "title" column off. maybe_push_columns/3 emits the
      # push_event with the full active-fields map.
      view
      |> element("input[phx-click='toggle_column'][phx-value-field='title']")
      |> render_click()

      expected_key = PrefKeys.columns(@resource_mod)

      assert_push_event(view, @event_name, %{key: ^expected_key, value: value})

      # title was just toggled, so it must now be false; other fields remain true.
      assert is_map(value)
      assert value["title"] == false
    end
  end
end
