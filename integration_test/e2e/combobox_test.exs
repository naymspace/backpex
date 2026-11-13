defmodule Backpex.E2E.ComboboxTest do
  use Backpex.E2ECase, async: true

  # The fixture is `Backpex.Test.ComboboxLive`. Field comboboxes have the id `combobox_<field>`.

  defp trigger(id), do: "##{id}-trigger"
  defp search(id), do: "##{id}-popup [data-part=search]"
  defp option(id, value), do: "##{id}-listbox [data-part=option][data-value='#{value}']"
  defp badge(id, value), do: "##{id}-value [data-part=badge][data-value='#{value}']"

  defp visit_fixture(conn) do
    conn
    |> visit(~p"/admin/combobox")
    |> assert_has("body .phx-connected")
  end

  defp open(conn, id) do
    conn
    |> click(trigger(id))
    |> assert_open(id)
  end

  defp assert_open(conn, id) do
    conn
    |> assert_has("#{trigger(id)}[aria-expanded=true]")
    |> assert_has("##{id}[data-open] ##{id}-listbox")
  end

  defp assert_closed(conn, id) do
    conn
    |> assert_has("#{trigger(id)}[aria-expanded=false]")
    |> refute_has("##{id}-listbox")
  end

  # JavaScript that polls `condition` for up to 1.5 s and returns whether it became true: the hook and LiveView update
  # the DOM asynchronously, and `assert_has` cannot see hidden inputs.
  defp poll_js(condition) do
    """
    (async () => {
      const deadline = Date.now() + 1500
      while (Date.now() < deadline) {
        if (#{condition}) return true
        await new Promise((resolve) => setTimeout(resolve, 25))
      }
      return false
    })()
    """
  end

  # The form state of a combobox: the submitted values and what it shows.
  defp state_js(id) do
    """
    ((root) => ({
      anchor: root.querySelector('[data-part=anchor]').value,
      values: Array.from(root.querySelectorAll('[data-part=inputs] input[type=hidden]'), (input) => input.value),
      badges: Array.from(root.querySelectorAll('[data-part=value] [data-part=badge]'), (badge) =>
        [badge.dataset.value, badge.querySelector('[data-part=badge-label]').textContent.trim(),
         badge.querySelectorAll('[data-part=badge-remove] svg, [data-part=badge-remove] [class*=hero-]').length > 0]),
      label: root.querySelector('[data-part=value-label]:not([hidden])')?.textContent.trim() ?? null,
      placeholder: !root.querySelector('[data-part=placeholder]').hidden,
      selected: Array.from(root.querySelectorAll('[data-part=option][aria-selected=true]'), (option) => option.dataset.value)
    }))(document.getElementById('#{id}'))
    """
  end

  # Waits until the combobox shows the expected state; `expected` is a subset of the keys of `state_js/1`.
  defp assert_state(conn, id, expected) do
    expected_json = expected |> Map.new() |> Phoenix.json_library().encode!()

    shows_expected = """
    ((state, expected) => Object.keys(expected).every((key) => JSON.stringify(state[key]) === JSON.stringify(expected[key])))(#{state_js(id)}, #{expected_json})
    """

    conn
    |> evaluate(poll_js(shows_expected))
    |> evaluate(state_js(id), fn state ->
      expected = Map.new(expected, fn {key, value} -> {to_string(key), value} end)
      assert Map.take(state, Map.keys(expected)) == expected
    end)
  end

  defp last_change(conn, fun) do
    evaluate(conn, "document.getElementById('last-change').textContent", fn
      "" -> fun.(nil)
      json -> json |> Phoenix.json_library().decode!() |> fun.()
    end)
  end

  defp assert_focus(conn, selector), do: assert_has(conn, "#{selector}:focus")

  describe "single selection" do
    test "selects with the mouse, sends phx-change for the field and shows errors only after the field was used",
         %{conn: conn} do
      conn
      |> visit_fixture()
      |> refute_has("#combobox_country-errors")
      |> open("combobox_fruit")
      |> click(option("combobox_fruit", "lemon"))
      |> assert_closed("combobox_fruit")
      |> assert_focus(trigger("combobox_fruit"))
      |> assert_state("combobox_fruit", anchor: "lemon", label: "Lemon", placeholder: false, selected: ["lemon"])
      |> assert_has("#changes", text: "Changes: 1")
      |> last_change(fn params ->
        assert params["_target"] == ["combobox", "fruit"]
        assert params["combobox"]["fruit"] == "lemon"
        assert Map.has_key?(params["combobox"], "_unused_country")
        refute Map.has_key?(params["combobox"], "_unused_fruit")
      end)
      # The required country was not used, so its error stays hidden.
      |> refute_has("#combobox_country-errors")
      |> assert_has("#{trigger("combobox_country")}:not([aria-invalid])")
      |> open("combobox_country")
      |> click(option("combobox_country", "at"))
      |> assert_state("combobox_country", anchor: "at", label: "Austria")
      |> assert_has("#changes", text: "Changes: 2")
      |> refute_has("#combobox_country-errors")
      |> click("#combobox_country [data-part=clear]")
      |> assert_state("combobox_country", anchor: "", label: nil, placeholder: true, selected: [])
      |> assert_focus(trigger("combobox_country"))
      |> assert_has("#combobox_country-errors", text: "can't be blank")
      |> assert_has("#{trigger("combobox_country")}[aria-invalid=true]")
      |> last_change(fn params ->
        assert params["_target"] == ["combobox", "country"]
        assert params["combobox"]["country"] == ""
      end)
      # Selecting the selected option again keeps it.
      |> open("combobox_fruit")
      |> click(option("combobox_fruit", "lemon"))
      |> assert_closed("combobox_fruit")
      |> assert_state("combobox_fruit", anchor: "lemon", label: "Lemon")
      # Disabled options can't be selected.
      |> open("combobox_fruit")
      |> assert_has("#{option("combobox_fruit", "blueberry")}[aria-disabled=true]")
      |> evaluate("document.querySelector(\"#{option("combobox_fruit", "blueberry")}\").click()")
      |> assert_open("combobox_fruit")
      |> assert_state("combobox_fruit", anchor: "lemon")
      # Submitting sends the values; the disabled combobox is not submitted, the readonly ones are.
      |> click("h1")
      |> assert_closed("combobox_fruit")
      |> click("#submit-button")
      |> assert_has("#last-submit", text: "lemon")
      |> evaluate("document.getElementById('last-submit').textContent", fn json ->
        params = Phoenix.json_library().decode!(json)["combobox"]
        assert params["fruit"] == "lemon"
        assert params["readonly_choice"] == "b"
        assert params["readonly_tags"] == ["a", "c"]
        assert params["tags"] == ""
        refute Map.has_key?(params, "disabled_choice")
      end)
    end

    test "filters locally without sending phx-change and resets the query on close", %{conn: conn} do
      conn
      |> visit_fixture()
      |> open("combobox_country")
      |> assert_focus(search("combobox_country"))
      |> type(search("combobox_country"), "TURK")
      |> assert_has("##{"combobox_country"}-listbox [data-part=option]", count: 1)
      |> assert_has(option("combobox_country", "tr"), text: "Türkiye")
      |> assert_has("#{option("combobox_country", "tr")}[data-active]")
      |> type(search("combobox_country"), "xyz")
      |> refute_has("#combobox_country-listbox [data-part=option]")
      |> assert_has("#combobox_country-popup [data-part=empty]", text: "No options found")
      |> assert_has("#changes", text: "Changes: 0")
      |> last_change(&assert(&1 == nil))
      |> press(search("combobox_country"), "Escape")
      |> assert_closed("combobox_country")
      |> assert_focus(trigger("combobox_country"))
      |> open("combobox_country")
      |> assert_has(search("combobox_country"), value: "")
      |> assert_has("#combobox_country-listbox [data-part=option]", count: 21)
      |> refute_has("#combobox_country-popup [data-part=empty]")
      # Groups without a matching option are hidden, and the custom empty slot replaces the default text.
      |> click("h1")
      |> open("combobox_fruit")
      |> type(search("combobox_fruit"), "berry")
      |> refute_has("#combobox_fruit-listbox [data-part=group-label]", text: "Citrus")
      |> assert_has("#combobox_fruit-listbox [data-part=group-label]", text: "Berries")
      |> assert_has("#combobox_fruit-listbox [data-part=option]", count: 3)
      # The disabled Blueberry is skipped for the active option.
      |> assert_has("#{option("combobox_fruit", "strawberry")}[data-active]")
      |> click("h1")
      |> open("combobox_user")
      |> assert_has(option("combobox_user", "ada") <> " [data-email]", text: "ada@example.com")
      |> type(search("combobox_user"), "nobody")
      |> assert_has("#combobox_user-popup [data-part=empty]", text: "No user matches")
      |> assert_has("#changes", text: "Changes: 0")
    end
  end

  describe "keyboard" do
    test "operates a searchable combobox with the keyboard only", %{conn: conn} do
      active_descendant =
        "document.querySelector('#{search("combobox_country")}').getAttribute('aria-activedescendant')"

      conn
      |> visit_fixture()
      |> press(trigger("combobox_country"), "ArrowDown")
      |> assert_open("combobox_country")
      |> assert_focus(search("combobox_country"))
      |> assert_has("#{option("combobox_country", "de")}[data-active]")
      |> evaluate(active_descendant, &assert(&1 == "combobox_country-option-0"))
      |> press(search("combobox_country"), "ArrowDown")
      |> press(search("combobox_country"), "ArrowDown")
      |> assert_has("#{option("combobox_country", "ch")}[data-active]")
      |> evaluate(active_descendant, &assert(&1 == "combobox_country-option-2"))
      |> press(search("combobox_country"), "ArrowUp")
      |> assert_has("#{option("combobox_country", "at")}[data-active]")
      |> press(search("combobox_country"), "Enter")
      |> assert_closed("combobox_country")
      |> assert_focus(trigger("combobox_country"))
      |> assert_state("combobox_country", anchor: "at", label: "Austria")
      # Enter on the closed trigger opens instead of submitting; the selected option is active.
      |> press(trigger("combobox_country"), "Enter")
      |> assert_open("combobox_country")
      |> assert_has("#{option("combobox_country", "at")}[data-active]")
      |> type(search("combobox_country"), "fr")
      |> press(search("combobox_country"), "Enter")
      |> assert_state("combobox_country", anchor: "fr", label: "France")
      |> evaluate("document.getElementById('last-submit').textContent", &assert(&1 == ""))
      # Tab closes the popup and moves on.
      |> press(trigger("combobox_country"), "ArrowUp")
      |> assert_open("combobox_country")
      |> press(search("combobox_country"), "Tab")
      |> assert_closed("combobox_country")
      |> evaluate("document.getElementById('combobox_country').contains(document.activeElement)", &refute/1)
      # Backspace clears a clearable combobox.
      |> press(trigger("combobox_country"), "Backspace")
      |> assert_state("combobox_country", anchor: "", placeholder: true)
      |> assert_has("#combobox_country-errors", text: "can't be blank")
      # A printable key on the trigger opens the popup and starts the search.
      |> press(trigger("combobox_country"), "g")
      |> assert_open("combobox_country")
      |> assert_has(search("combobox_country"), value: "g")
    end

    test "operates a combobox without search with the keyboard, including typeahead", %{conn: conn} do
      conn
      |> visit_fixture()
      |> press(trigger("combobox_size"), "Space")
      |> assert_open("combobox_size")
      |> assert_focus(trigger("combobox_size"))
      |> assert_has("#{option("combobox_size", "s")}[data-active]")
      |> evaluate(
        "document.querySelector('#{trigger("combobox_size")}').getAttribute('aria-activedescendant')",
        &assert(&1 == "combobox_size-option-0")
      )
      |> press(trigger("combobox_size"), "End")
      |> assert_has("#{option("combobox_size", "l")}[data-active]")
      |> press(trigger("combobox_size"), "ArrowDown")
      |> assert_has("#{option("combobox_size", "l")}[data-active]")
      |> press(trigger("combobox_size"), "Home")
      |> assert_has("#{option("combobox_size", "s")}[data-active]")
      |> press(trigger("combobox_size"), "ArrowDown")
      |> press(trigger("combobox_size"), "Space")
      |> assert_closed("combobox_size")
      |> assert_focus(trigger("combobox_size"))
      |> assert_state("combobox_size", anchor: "m", label: "Medium")
      # Typeahead opens the popup and activates the first match, a repeated character cycles through the matches.
      |> press(trigger("combobox_priority"), "h")
      |> assert_open("combobox_priority")
      |> assert_has("#{option("combobox_priority", "high")}[data-active]")
      |> press(trigger("combobox_priority"), "h")
      |> assert_has("#{option("combobox_priority", "highest")}[data-active]")
      |> press(trigger("combobox_priority"), "Enter")
      |> assert_closed("combobox_priority")
      |> assert_state("combobox_priority", anchor: "highest", label: "Highest")
      |> press(trigger("combobox_priority"), "Escape")
      |> assert_closed("combobox_priority")
    end
  end

  describe "multiple selection" do
    test "toggles values, respects max and removes them by badge, Backspace and clear", %{conn: conn} do
      id = "combobox_tags"

      conn
      |> visit_fixture()
      |> open(id)
      |> click(option(id, "Elixir"))
      |> click(option(id, "Phoenix"))
      |> click(option(id, "Ecto"))
      |> assert_open(id)
      |> assert_state(id,
        anchor: "",
        values: ["Elixir", "Phoenix", "Ecto"],
        badges: [["Elixir", "Elixir", true], ["Phoenix", "Phoenix", true], ["Ecto", "Ecto", true]],
        selected: ["Elixir", "Phoenix", "Ecto"]
      )
      |> assert_has("#changes", text: "Changes: 3")
      |> last_change(fn params ->
        assert params["_target"] == ["combobox", "tags"]
        assert params["combobox"]["tags"] == ["Elixir", "Phoenix", "Ecto"]
      end)
      # With max reached, the other options are disabled.
      |> assert_has("#{option(id, "Erlang")}[aria-disabled=true]")
      |> assert_has("#{option(id, "Elixir")}:not([aria-disabled])")
      |> evaluate("document.querySelector(\"#{option(id, "Erlang")}\").click()")
      |> assert_state(id, values: ["Elixir", "Phoenix", "Ecto"])
      # Clicking a selected option deselects it, which enables the others again.
      |> click(option(id, "Phoenix"))
      |> assert_state(id, values: ["Elixir", "Ecto"])
      |> assert_has("#{option(id, "Erlang")}:not([aria-disabled])")
      |> click(option(id, "Erlang"))
      |> click("#{badge(id, "Elixir")} [data-part=badge-remove]")
      |> assert_open(id)
      |> assert_focus(trigger(id))
      |> assert_state(id, values: ["Ecto", "Erlang"], badges: [["Ecto", "Ecto", true], ["Erlang", "Erlang", true]])
      |> press(trigger(id), "Escape")
      |> assert_closed(id)
      |> press(trigger(id), "Backspace")
      |> assert_state(id, values: ["Ecto"], badges: [["Ecto", "Ecto", true]])
      |> click("##{id} [data-part=clear]")
      |> assert_state(id, anchor: "", values: [], badges: [], placeholder: true)
      |> assert_has("#changes", text: "Changes: 8")
      |> last_change(fn params ->
        assert params["_target"] == ["combobox", "tags"]
        assert params["combobox"]["tags"] == ""
      end)
    end

    test "selects and deselects all options the search shows and counts the selection", %{conn: conn} do
      id = "combobox_all_tags"
      count = "##{id} [data-part=selected-count]"
      select_all = "##{id} [data-part=select-all-button]"
      deselect_all = "##{id} [data-part=deselect-all-button]"

      conn
      |> visit_fixture()
      |> open(id)
      |> assert_has(count, text: "0", exact: true)
      |> refute_has("#{select_all}[aria-disabled=true]")
      |> assert_has("#{deselect_all}[aria-disabled=true]")
      # "Select all" only selects what the search shows, and a click on it leaves the focus in the search input.
      |> type(search(id), "al")
      |> assert_has("##{id}-listbox [data-part=option]", count: 2)
      |> click(select_all)
      |> assert_state(id, values: ~w(alpha alabama), selected: ~w(alpha alabama))
      |> assert_has(count, text: "2", exact: true)
      |> assert_has("#{select_all}[aria-disabled=true]")
      |> assert_focus(search(id))
      |> assert_open(id)
      |> assert_has("#changes", text: "Changes: 1")
      |> last_change(fn change ->
        assert change["combobox"]["all_tags"] == ~w(alpha alabama)
        assert change["_target"] == ~w(combobox all_tags)
      end)
      # Without the search, the disabled option is left out.
      |> press(search(id), "Backspace")
      |> press(search(id), "Backspace")
      |> assert_has("##{id}-listbox [data-part=option]", count: 5)
      |> refute_has("#{select_all}[aria-disabled=true]")
      |> click(select_all)
      |> assert_state(id, values: ~w(alpha alabama beta gamma))
      |> assert_has(count, text: "4", exact: true)
      # "Deselect all" also only acts on what the search shows.
      |> type(search(id), "al")
      |> click(deselect_all)
      |> assert_state(id, values: ~w(beta gamma))
      |> assert_has(count, text: "2", exact: true)
      |> assert_has("#{deselect_all}[aria-disabled=true]")
      |> assert_has("#changes", text: "Changes: 3")
      |> last_change(&assert(&1["combobox"]["all_tags"] == ~w(beta gamma)))
      # With the keyboard: Tab moves from the search input to the buttons, which keep the focus and the popup open.
      |> press(search(id), "Backspace")
      |> press(search(id), "Backspace")
      |> press(search(id), "Tab")
      |> assert_focus(select_all)
      |> press(select_all, "Enter")
      |> assert_state(id, values: ~w(beta gamma alpha alabama))
      |> assert_focus(select_all)
      |> assert_open(id)
      |> press(select_all, "Tab")
      |> assert_focus(deselect_all)
      |> press(deselect_all, "Enter")
      |> assert_state(id, values: [], placeholder: true)
      |> assert_has(count, text: "0", exact: true)
      |> assert_focus(deselect_all)
      |> assert_has("#changes", text: "Changes: 5")
      |> last_change(&assert(&1["combobox"]["all_tags"] == ""))
    end

    test "is controlled by commands and announces changes", %{conn: conn} do
      conn
      |> visit_fixture()
      |> evaluate("""
      window.comboboxChanges = []
      document.addEventListener('combobox:change', (event) => window.comboboxChanges.push([event.target.id, event.detail.value]))
      """)
      |> click("#open-tags")
      |> assert_open("combobox_tags")
      |> click("#close-tags")
      |> assert_closed("combobox_tags")
      |> open("combobox_languages")
      |> type(search("combobox_languages"), "an")
      |> click("#languages-select-all")
      # Selects the visible options only: German, Spanish, Italian.
      |> assert_state("combobox_languages", values: ["de", "es", "it"])
      |> click("#languages-clear")
      |> assert_state("combobox_languages", values: [], badges: [])
      |> click("h1")
      |> open("combobox_tags")
      |> click(option("combobox_tags", "Ecto"))
      |> click("#clear-tags")
      |> assert_state("combobox_tags", values: [])
      |> click(trigger("combobox_country"))
      |> click(option("combobox_country", "de"))
      |> evaluate("window.comboboxChanges", fn changes ->
        assert changes == [
                 ["combobox_languages", ["de", "es", "it"]],
                 ["combobox_languages", []],
                 ["combobox_tags", ["Ecto"]],
                 ["combobox_tags", []],
                 ["combobox_country", "de"]
               ]
      end)
    end
  end

  describe "server patches" do
    test "keep an open popup, its query, focus and active option", %{conn: conn} do
      id = "combobox_country"

      conn
      |> visit_fixture()
      |> open(id)
      |> type(search(id), "land")
      |> press(search(id), "ArrowDown")
      |> assert_has("#{option(id, "nl")}[data-active]")
      |> evaluate("document.getElementById('server-patch-button').click()")
      |> assert_has("#patches", text: "Patches: 1")
      |> assert_open(id)
      |> assert_focus(search(id))
      |> assert_has(search(id), value: "land")
      |> assert_has("#{option(id, "nl")}[data-active]")
      |> refute_has(option(id, "at"))
      |> evaluate(
        "document.querySelector('#{search(id)}').getAttribute('aria-activedescendant')",
        &assert(&1 == "#{id}-option-5")
      )
      # The patch after a selection in a multiple combobox leaves one badge and input per value.
      |> click("h1")
      |> open("combobox_tags")
      |> click(option("combobox_tags", "Ecto"))
      |> click(option("combobox_tags", "Elixir"))
      |> evaluate("document.getElementById('server-patch-button').click()")
      |> click(option("combobox_tags", "Ecto"))
      |> assert_has("#patches", text: "Patches: 2")
      |> assert_open("combobox_tags")
      |> assert_state("combobox_tags", values: ["Elixir"], badges: [["Elixir", "Elixir", true]], selected: ["Elixir"])
      |> click(option("combobox_tags", "Tailwind"))
      |> assert_has("#changes", text: "Changes: 4")
      |> assert_state("combobox_tags",
        values: ["Elixir", "Tailwind"],
        badges: [["Elixir", "Elixir", true], ["Tailwind", "Tailwind", true]]
      )
    end

    test "show the value the server rendered when it overrules the selection", %{conn: conn} do
      id = "combobox_restricted"

      conn
      |> visit_fixture()
      # The server renders a value different from the chosen one and from the one it had.
      |> open(id)
      |> click(option(id, "other"))
      |> assert_has("#changes", text: "Changes: 1")
      |> assert_state(id, anchor: "allowed", label: "Allowed", selected: ["allowed"])
      |> open("combobox_restricted_tags")
      |> click(option("combobox_restricted_tags", "other"))
      |> assert_has("#changes", text: "Changes: 2")
      |> assert_state("combobox_restricted_tags",
        values: ["allowed"],
        badges: [["allowed", "Allowed", true]],
        selected: ["allowed"]
      )
    end

    # When the server keeps the value it had, its patch does not touch the field, so the admin's choice stays in the
    # browser, as it does in a native select. The moduledoc says so.
    test "keep the chosen value when the server renders the value it had, like a native select", %{conn: conn} do
      conn
      |> visit_fixture()
      |> select("#native-restricted", "Native restricted", option: "Allowed")
      |> assert_has("#changes", text: "Changes: 1")
      |> select("#native-restricted", "Native restricted", option: "Rejected")
      |> assert_has("#changes", text: "Changes: 2")
      |> last_change(&assert(&1["combobox"]["native_restricted"] == "rejected"))
      |> evaluate("document.getElementById('native-restricted').value", &assert(&1 == "rejected"))
      |> open("combobox_restricted")
      |> click(option("combobox_restricted", "allowed"))
      |> assert_has("#changes", text: "Changes: 3")
      |> open("combobox_restricted")
      |> click(option("combobox_restricted", "rejected"))
      |> assert_has("#changes", text: "Changes: 4")
      |> assert_state("combobox_restricted", anchor: "rejected", label: "Rejected")
    end

    @tag browser_context_opts: [viewport: %{width: 1280, height: 520}]
    test "keep the scroll position of the listbox", %{conn: conn} do
      id = "combobox_long_tags"
      listbox = "document.getElementById('#{id}-listbox')"

      conn
      |> visit_fixture()
      |> open(id)
      # The viewport is so short that the room next to the control limits the popup, not its class.
      |> evaluate("parseFloat(document.getElementById('#{id}-popup').style.maxHeight)", &assert(&1 < 320))
      # Scrolled to the end, where measuring a taller popup would clamp the scroll position.
      |> evaluate("#{listbox}.scrollTop = #{listbox}.scrollHeight; #{listbox}.scrollTop", fn bottom ->
        assert bottom > 0
        Process.put(:bottom, bottom)
      end)
      |> click(option(id, "item-30"))
      |> assert_state(id, values: ["item-30"])
      |> assert_has("#changes", text: "Changes: 1")
      |> evaluate("#{listbox}.scrollTop", &assert(&1 == Process.get(:bottom)))
      |> evaluate("document.getElementById('server-patch-button').click()")
      |> assert_has("#patches", text: "Patches: 1")
      |> evaluate("#{listbox}.scrollTop", &assert(&1 == Process.get(:bottom)))
      # Scrolling the page moves the popup, not the options.
      |> evaluate("#{listbox}.scrollTop = 150")
      |> evaluate("window.scrollBy(0, 10)")
      |> evaluate("new Promise((resolve) => requestAnimationFrame(() => resolve()))")
      |> evaluate("#{listbox}.scrollTop", &assert(&1 == 150))
    end
  end

  describe "server search" do
    test "searches on the server and keeps the label of a selected option that the search filtered out",
         %{conn: conn} do
      id = "combobox_person"

      conn
      |> visit_fixture()
      |> open(id)
      |> type(search(id), "rené")
      |> assert_has("#people-query", text: "rené")
      |> assert_has("##{id}-listbox [data-part=option]", count: 1)
      |> assert_has("#{option(id, "rené")}[data-active]")
      |> press(search(id), "Enter")
      |> assert_state(id, anchor: "rené", label: "René")
      |> assert_has("#changes", text: "Changes: 1")
      # Closing pushed the empty query.
      |> assert_has("#people-query", text: "", exact: true)
      |> open(id)
      |> type(search(id), "ada")
      |> assert_has("#people-query", text: "ada")
      |> refute_has(option(id, "rené"))
      |> assert_state(id, anchor: "rené", label: "René")
      |> press(search(id), "Escape")
      # Multiple: badges keep the labels of options from earlier searches.
      |> open("combobox_people")
      |> type(search("combobox_people"), "guido")
      |> assert_has("#people-query", text: "guido")
      |> click(option("combobox_people", "guido"))
      |> type(search("combobox_people"), "x")
      |> assert_has("#people-query", text: "guidox")
      |> select_all_text(search("combobox_people"))
      |> type(search("combobox_people"), "linus")
      |> assert_has("#people-query", text: "linus")
      |> click(option("combobox_people", "linus"))
      |> assert_state("combobox_people",
        values: ["guido", "linus"],
        badges: [["guido", "Guido", true], ["linus", "Linus", true]]
      )
      |> assert_has("#changes", text: "Changes: 3")
      |> assert_state(id, anchor: "rené", label: "René")
    end

    test "pushes the search to phx-target and shows the loading state while it is pending", %{conn: conn} do
      id = "component-person"

      conn
      |> visit_fixture()
      |> open(id)
      |> type(search(id), "slow")
      |> assert_has("##{id}[data-loading] ##{id}-listbox[aria-busy]")
      |> assert_has("#component-query", text: "slow")
      |> refute_has("##{id}[data-loading]")
      |> refute_has("##{id}-listbox[aria-busy]")
      |> select_all_text(search(id))
      |> type(search(id), "gu")
      |> assert_has("#component-query", text: "gu")
      |> assert_has("##{id}-listbox [data-part=option]", count: 1)
      |> click(option(id, "guido"))
      |> assert_has("#component-value", text: "guido")
      |> assert_state(id, anchor: "guido", label: "Guido")
      # The LiveView itself got no search and no change.
      |> assert_has("#search-events", text: "0", exact: true)
      |> assert_has("#changes", text: "Changes: 0")
    end
  end

  describe "popup" do
    test "closes on Escape without closing a surrounding dialog or Backpex modal", %{conn: conn} do
      conn
      |> visit_fixture()
      |> click("#open-dialog")
      |> assert_has("#combobox-dialog[open]")
      |> open("combobox_dialog_choice")
      |> click(option("combobox_dialog_choice", "ch"))
      |> assert_state("combobox_dialog_choice", anchor: "ch", label: "Switzerland")
      |> assert_has("#combobox-dialog[open]")
      |> press(trigger("combobox_dialog_choice"), "Enter")
      |> assert_open("combobox_dialog_choice")
      |> press(search("combobox_dialog_choice"), "Escape")
      |> assert_closed("combobox_dialog_choice")
      |> assert_has("#combobox-dialog[open]")
      |> press(trigger("combobox_dialog_choice"), "Escape")
      |> refute_has("#combobox-dialog[open]")
      |> click("#open-modal")
      |> assert_has("#backpex-modal")
      |> open("modal-choice")
      |> press(search("modal-choice"), "Escape")
      |> assert_closed("modal-choice")
      |> assert_has("#backpex-modal")
      |> press(trigger("modal-choice"), "Escape")
      |> refute_has("#backpex-modal")
    end

    test "closes on a click outside and when focus leaves", %{conn: conn} do
      conn
      |> visit_fixture()
      |> open("combobox_country")
      |> click("h1")
      |> assert_closed("combobox_country")
      |> open("combobox_country")
      |> open("combobox_fruit")
      |> assert_closed("combobox_country")
      |> evaluate("document.getElementById('standalone-trigger').focus()")
      |> assert_closed("combobox_fruit")
    end

    test "opens above a control near the bottom of the viewport", %{conn: conn} do
      id = "combobox_bottom_choice"

      conn
      |> visit_fixture()
      |> evaluate("document.getElementById('#{id}').scrollIntoView({ block: 'end' })")
      |> evaluate("document.getElementById('#{id}-trigger').click()")
      |> assert_open(id)
      |> assert_has("##{id}-popup[data-placement=top]")
      |> evaluate(
        """
        (() => {
          const control = document.querySelector('##{id} [data-part=control]').getBoundingClientRect()
          const popup = document.getElementById('#{id}-popup').getBoundingClientRect()
          return [popup.top >= 0, popup.bottom <= control.top, popup.width >= control.width - 1]
        })()
        """,
        &assert(&1 == [true, true, true])
      )
    end

    test "follows the control when the layout shifts without a scroll or resize", %{conn: conn} do
      id = "combobox_country"

      # `[top of the control, popup touches the control below or above it, popup starts at its left edge]`
      geometry = """
      (() => {
        const control = document.querySelector('##{id} [data-part=control]').getBoundingClientRect()
        const popup = document.getElementById('#{id}-popup').getBoundingClientRect()
        const below = Math.abs(popup.top - control.bottom - 4) < 1
        const above = Math.abs(control.top - popup.bottom - 4) < 1
        return [Math.round(control.top), below || above, Math.abs(popup.left - control.left) < 1]
      })()
      """

      conn
      |> visit_fixture()
      |> open(id)
      |> evaluate(poll_js("#{geometry}[1]"), &assert/1)
      |> evaluate(geometry, fn [top, true, true] -> send(self(), {:control_top, top}) end)
      |> evaluate("""
      document.getElementById('combobox-form').insertAdjacentHTML('beforebegin', '<div id="shift" style="height: 120px"></div>')
      """)
      |> assert_has("#shift")
      |> evaluate(poll_js("#{geometry}[1]"), &assert/1)
      |> evaluate(geometry, fn [top, true, true] ->
        assert_received {:control_top, top_before}
        assert top >= top_before + 120
      end)
    end

    test "keeps the height of a native input of its size with and without a value", %{conn: conn} do
      heights = """
      ['xs', 'sm', 'md', 'lg', 'xl'].map((size) => {
        const input = document.createElement('input')
        input.className = `input input-${size}`
        document.body.append(input)
        const native = input.getBoundingClientRect().height
        input.remove()
        return [size, document.querySelector(`#size-${size} [data-part=control]`).getBoundingClientRect().height, native]
      })
      """

      with_value =
        conn
        |> visit_fixture()
        |> evaluate(heights, fn result ->
          for [size, height, native] <- result, do: assert({size, height} == {size, native})
        end)

      ~w(xs sm md lg xl)
      |> Enum.reduce(with_value, &click(&2, "#size-#{&1} [data-part=clear]"))
      |> assert_state("size-xl", placeholder: true)
      |> evaluate(heights, fn result ->
        for [size, height, native] <- result, do: assert({size, height} == {size, native})
      end)
    end

    @tag browser_context_opts: [viewport: %{width: 360, height: 640}]
    test "fits a mobile viewport", %{conn: conn} do
      id = "combobox_tags"

      conn
      |> visit_fixture()
      |> open(id)
      |> evaluate(
        """
        (() => {
          const popup = document.getElementById('#{id}-popup').getBoundingClientRect()
          return [popup.left >= 0, popup.right <= document.documentElement.clientWidth, popup.bottom <= window.innerHeight]
        })()
        """,
        &assert(&1 == [true, true, true])
      )
      |> click(option(id, "LiveView"))
      |> assert_state(id, values: ["LiveView"])
      |> evaluate("document.documentElement.scrollWidth <= document.documentElement.clientWidth", &assert/1)
    end

    test "leaves nothing behind when the page is left while it is open", %{conn: conn} do
      conn
      |> visit_fixture()
      |> evaluate("""
      window.comboboxErrors = []
      window.addEventListener('error', (event) => window.comboboxErrors.push(event.message))
      const consoleError = console.error
      console.error = (...args) => { window.comboboxErrors.push(args.join(' ')); consoleError(...args) }
      """)
      |> open("combobox_person")
      |> type(search("combobox_person"), "a")
      |> evaluate(~s|document.querySelector('a[href="/admin/posts"]').click()|)
      |> assert_path("/admin/posts")
      |> assert_has("body .phx-connected")
      |> evaluate("""
      document.dispatchEvent(new Event('scroll'))
      window.dispatchEvent(new Event('resize'))
      document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }))
      new Promise((resolve) => setTimeout(resolve, 300))
      """)
      |> evaluate("[window.comboboxErrors, document.querySelectorAll(':popover-open').length]", fn result ->
        assert result == [[], 0]
      end)
    end
  end

  defp select_all_text(conn, selector) do
    evaluate(conn, "document.querySelector('#{selector}').select()")
  end
end
