defmodule Backpex.E2E.FiltersTest do
  use Backpex.E2ECase, async: true

  # The badges of the active filters next to the filter dropdown of the index view.

  @long_name String.duplicate("Verylongname", 10)

  defp visit_with_long_user_filter(session) do
    [first, second] = for _index <- 1..2, do: insert(:post, user: insert(:user, last_name: @long_name))

    session
    |> visit(~p"/admin/posts?filters[user_id][]=#{first.user_id}&filters[user_id][]=#{second.user_id}")
    |> assert_has(by_role(:button, name: "Clear Users filter", exact: true))
  end

  defp assert_badge_fits(session) do
    widths =
      Fluffy.Playwright.evaluate(session, """
      (() => {
        const badge = document.querySelector('button[aria-label="Clear Users filter"]').closest('.indicator')
        return {
          page: document.documentElement.scrollWidth,
          viewport: window.innerWidth,
          badgeRight: badge.getBoundingClientRect().right
        }
      })()
      """)

    assert widths["page"] <= widths["viewport"]
    assert widths["badgeRight"] <= widths["viewport"]
  end

  describe "filter badge" do
    test "keeps a long value inside the page", %{session: session} do
      session
      |> visit_with_long_user_filter()
      |> assert_badge_fits()
    end

    @tag Playwright.Test.use(viewport: %{width: 360, height: 640})
    test "keeps a long value inside a mobile viewport", %{session: session} do
      session
      |> visit_with_long_user_filter()
      |> assert_badge_fits()
    end
  end
end
