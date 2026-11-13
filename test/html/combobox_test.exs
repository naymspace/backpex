defmodule Backpex.HTML.ComboboxTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2, to_form: 2]
  import Phoenix.LiveViewTest

  alias Backpex.HTML.Combobox

  defp render_combobox(assigns) do
    assigns = if assigns[:field], do: assigns, else: Keyword.merge([id: "choice", name: "choice"], assigns)

    (&Combobox.combobox/1)
    |> render_component(assigns)
    |> LazyHTML.from_fragment()
  end

  defp render_template(fun) do
    fun |> render_component(%{}) |> LazyHTML.from_fragment()
  end

  defp attribute(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp texts(doc, selector) do
    doc |> LazyHTML.query(selector) |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  # The options as `{id, value, label, aria-disabled}`.
  defp options(doc) do
    doc
    |> LazyHTML.query("[data-part=option]")
    |> Enum.map(fn option ->
      [id] = LazyHTML.attribute(option, "id")
      [value] = LazyHTML.attribute(option, "data-value")
      [label] = LazyHTML.attribute(option, "data-label")
      {id, value, label, LazyHTML.attribute(option, "aria-disabled") == ["true"]}
    end)
  end

  # Serializes the successful controls in DOM order, as a browser submits them.
  defp submitted_params(doc) do
    doc
    |> LazyHTML.query("input[name]:not([disabled])")
    |> Enum.map(fn input ->
      [name] = LazyHTML.attribute(input, "name")
      [value] = LazyHTML.attribute(input, "value")
      {name, value}
    end)
    |> URI.encode_query()
    |> Plug.Conn.Query.decode()
  end

  describe "options" do
    test "accepts every format of options_for_select/2 and numbers the options across groups" do
      doc =
        render_combobox(
          options: [
            "Plain",
            :atom,
            42,
            {"Tuple", :tuple},
            [key: "Keyword", value: "keyword", disabled: true],
            %{label: "Map", value: 7},
            :hr,
            {:hr, nil},
            {"Group", [{"In group", "in_group"}, "Bare"]},
            {"Map group", %{"Mapped" => "mapped"}}
          ]
        )

      assert options(doc) == [
               {"choice-option-0", "Plain", "Plain", false},
               {"choice-option-1", "atom", "atom", false},
               {"choice-option-2", "42", "42", false},
               {"choice-option-3", "tuple", "Tuple", false},
               {"choice-option-4", "keyword", "Keyword", true},
               {"choice-option-5", "7", "Map", false},
               {"choice-option-6", "in_group", "In group", false},
               {"choice-option-7", "Bare", "Bare", false},
               {"choice-option-8", "mapped", "Mapped", false}
             ]

      assert texts(doc, "[data-part=group-label]") == ["Group", "Map group"]
      assert attribute(doc, "[data-part=group]", "role") == ["group", "group"]
      assert attribute(doc, "[data-part=group]", "aria-labelledby") == ["choice-group-0-label", "choice-group-1-label"]
      assert attribute(doc, "#choice-group-1-label", "data-part") == ["group-label"]
      assert texts(doc, "[aria-labelledby=choice-group-0-label] [data-part=option]") == ["In group", "Bare"]
      # A disabled option is marked as disabled by the server, so the hook can tell it from one disabled by `max`.
      assert attribute(doc, "[data-part=option][data-disabled]", "data-value") == ["keyword"]
    end

    test "puts the options of a group inside a group into the outer group" do
      doc = render_combobox(options: [{"Outer", [{"Inner", [{"Nested", "nested"}]}, {"Direct", "direct"}]}])

      assert texts(doc, "[data-part=group-label]") == ["Outer"]
      assert texts(doc, "[aria-labelledby=choice-group-0-label] [data-part=option]") == ["Nested", "Direct"]
    end

    test "accepts a keyword list of label and value, like a native select" do
      doc = render_combobox(options: [Admin: "admin", User: "user"], value: "user")

      assert options(doc) == [{"choice-option-0", "admin", "Admin", false}, {"choice-option-1", "user", "User", false}]
      assert texts(doc, "[data-part=value-label]") == ["User"]
    end

    test "raises on an option it does not understand" do
      assert_raise ArgumentError, ~r/expected a :key or :label/, fn -> render_combobox(options: [%{value: "x"}]) end
      assert_raise ArgumentError, ~r/invalid combobox option/, fn -> render_combobox(options: [{"a", "b", "c"}]) end
    end

    test "passes the normalized option with its extra keys to the option slot" do
      assigns = %{users: [%{label: "Ada", value: 1, email: "ada@example.com"}]}

      doc =
        render_template(fn _assigns ->
          assigns = assigns

          ~H"""
          <Combobox.combobox id="user" name="user" options={@users}>
            <:option :let={user}>
              <span data-option-label>{user.label}</span>
              <span data-option-email>{user.email} {user.value} {user.disabled}</span>
            </:option>
          </Combobox.combobox>
          """
        end)

      assert texts(doc, "[data-option-label]") == ["Ada"]
      assert texts(doc, "[data-option-email]") == ["ada@example.com 1 false"]
    end
  end

  describe "selection" do
    test "a single combobox renders the selected label, state and form value" do
      doc = render_combobox(options: [{"One", 1}, {"Two", 2}], value: 2, clearable: true)

      assert attribute(doc, "[data-part=option]", "aria-selected") == ["false", "true"]
      assert texts(doc, "[data-part=value-label]") == ["Two"]
      assert attribute(doc, "[data-part=value-label]", "hidden") == []
      assert attribute(doc, "[data-part=placeholder]", "hidden") == [""]
      assert attribute(doc, "[data-part=clear]", "hidden") == []
      assert submitted_params(doc) == %{"choice" => "2"}

      # Values are compared as strings, so a list value uses its first element.
      assert render_combobox(options: [{"One", 1}], value: ["1"]) |> texts("[data-part=value-label]") == ["One"]
    end

    test "a single combobox without a value shows the placeholder and submits an empty string" do
      doc = render_combobox(options: [{"One", "1"}], value: nil, clearable: true)

      assert attribute(doc, "[data-part=placeholder]", "hidden") == []
      assert texts(doc, "[data-part=placeholder]") == ["Select an option..."]
      assert attribute(doc, "[data-part=value-label]", "hidden") == [""]
      assert attribute(doc, "[data-part=clear]", "hidden") == [""]
      assert submitted_params(doc) == %{"choice" => ""}
    end

    test "the anchor input is a hidden text input, so LiveView tracks whether it was used" do
      doc = render_combobox(options: ["a"], value: "a")

      [anchor] = LazyHTML.query(doc, "[data-part=inputs] [data-part=anchor]") |> Enum.to_list()
      assert LazyHTML.attribute(anchor, "type") == ["text"]
      assert LazyHTML.attribute(anchor, "hidden") == [""]
      assert LazyHTML.attribute(anchor, "tabindex") == ["-1"]
      assert LazyHTML.attribute(anchor, "aria-hidden") == ["true"]
      assert LazyHTML.attribute(anchor, "autocomplete") == ["off"]
      assert count(doc, "input[type=hidden]") == 0
    end

    test "a multiple combobox renders badges and one hidden input per value after an empty anchor" do
      doc =
        render_combobox(
          options: [{"Elixir", "ex"}, {"Erlang", "erl"}, {"Gleam", "gleam"}],
          value: ["erl", :ex, "erl", ""],
          multiple: true,
          max: 3
        )

      assert attribute(doc, "#choice", "data-multiple") == [""]
      assert attribute(doc, "[data-part=listbox]", "aria-multiselectable") == ["true"]
      assert attribute(doc, "[data-part=option]", "aria-selected") == ["true", "true", "false"]
      assert attribute(doc, "[data-part=value] [data-part=badge]", "data-value") == ["erl", "ex"]
      assert texts(doc, "[data-part=value] [data-part=badge-label]") == ["Erlang", "Elixir"]
      assert count(doc, "[data-part=value] [data-part=badge-remove]") == 2
      # The remove control is a mouse shortcut: hidden from assistive technology and not focusable.
      assert attribute(doc, "[data-part=badge-remove]", "aria-hidden") == ["true", "true"]
      assert attribute(doc, "[data-part=badge-remove]", "tabindex") == []
      # Plain elements without LiveView ids, so a patch never skips a badge the hook removed.
      assert attribute(doc, "[data-part=value] [data-phx-id], [data-part=value][data-phx-id]", "data-phx-id") == []
      assert count(doc, "[data-part=value-label]") == 0

      assert attribute(doc, "[data-part=inputs] input", "name") == ["choice", "choice[]", "choice[]"]
      assert submitted_params(doc) == %{"choice" => ["erl", "ex"]}
      assert submitted_params(render_combobox(options: ["a"], value: [], multiple: true)) == %{"choice" => ""}
    end

    test "the badge template has the markup of a rendered badge" do
      doc = render_combobox(options: [{"Elixir", "ex"}], value: ["ex"], multiple: true)

      [template] = doc |> LazyHTML.query("template[data-part=badge-template]") |> Enum.to_list()
      [_template, content] = Regex.run(~r{^<template[^>]*>(.*)</template>$}s, LazyHTML.to_html(template))
      template_badge = content |> LazyHTML.from_fragment() |> LazyHTML.query("[data-part=badge]")
      rendered_badge = LazyHTML.query(doc, "[data-part=value] [data-part=badge]")

      assert LazyHTML.attribute(template_badge, "class") == LazyHTML.attribute(rendered_badge, "class")
      assert count(template_badge, "[data-part=badge-label]") == 1
      assert count(template_badge, "[data-part=badge-remove]") == 1
    end

    test "disables the unselected options once max values are selected" do
      doc = render_combobox(options: ~w(a b c), value: ~w(a b), multiple: true, max: 2)

      assert attribute(doc, "#choice", "data-max") == ["2"]
      assert options(doc) |> Enum.map(&elem(&1, 3)) == [false, false, true]
      refute attribute(doc, "[data-part=option][data-value=c]", "data-disabled") == [""]
    end

    test "labels selected values from selected_options, then options, then the value itself" do
      doc =
        render_combobox(
          options: [{"Listed", "listed"}, {"Old label", "both"}],
          selected_options: [{"Searched", "searched"}, {"New label", "both"}],
          value: ~w(searched listed both unknown),
          multiple: true
        )

      assert texts(doc, "[data-part=value] [data-part=badge-label]") == ["Searched", "Listed", "New label", "unknown"]
      # selected_options only label the selection; they are not rendered as options.
      assert attribute(doc, "[data-part=option]", "data-value") == ~w(listed both)
    end
  end

  describe "form field" do
    defp field(params, errors) do
      form = to_form(params, as: :item, errors: errors, action: :validate)
      form[:country]
    end

    test "takes id, name and value from the field and shows its errors once it was used" do
      used = field(%{"country" => "de"}, country: {"is invalid", []})
      doc = render_combobox(field: used, label: "Country", options: [{"Germany", "de"}])

      assert attribute(doc, "[data-part=root]", "id") == ["item_country"]
      assert attribute(doc, "[data-part=anchor]", "name") == ["item[country]"]
      assert texts(doc, "[data-part=value-label]") == ["Germany"]
      assert texts(doc, "#item_country-errors") == ["is invalid"]
      assert attribute(doc, "#item_country-trigger", "aria-invalid") == ["true"]
      assert attribute(doc, "#item_country-trigger", "aria-describedby") == ["item_country-errors"]
      assert attribute(doc, "[data-part=control]", "class") |> hd() =~ "input-error"

      unused = field(%{"country" => "", "_unused_country" => ""}, country: {"can't be blank", []})
      doc = render_combobox(field: unused, options: [{"Germany", "de"}])

      assert count(doc, "#item_country-errors") == 0
      assert attribute(doc, "#item_country-trigger", "aria-invalid") == []
      refute attribute(doc, "[data-part=control]", "class") |> hd() =~ "input-error"
    end

    test "translates errors, hides them on request and lets an explicit id, name and value win" do
      used = field(%{"country" => "de"}, country: {"is invalid", []})

      doc =
        render_combobox(
          id: "custom",
          name: "custom_name",
          value: "at",
          field: used,
          options: [{"Germany", "de"}, {"Austria", "at"}],
          translate_error_fun: fn {msg, _opts} -> {"translated " <> msg, []} end
        )

      assert attribute(doc, "[data-part=root]", "id") == ["custom"]
      assert attribute(doc, "[data-part=anchor]", "name") == ["custom_name"]
      assert texts(doc, "[data-part=value-label]") == ["Austria"]
      assert texts(doc, "#custom-errors") == ["translated is invalid"]

      doc = render_combobox(id: "choice", field: used, options: [], hide_errors: true, error_class: "my-error")
      assert count(doc, "#choice-errors") == 0
      assert attribute(doc, "#choice-trigger", "aria-describedby") == []
      assert attribute(doc, "[data-part=control]", "class") |> hd() =~ "my-error"
    end

    test "requires an id without a field" do
      assert_raise ArgumentError, ~r/requires an id/, fn ->
        render_component(&Combobox.combobox/1, name: "x", options: [])
      end
    end
  end

  describe "disabled and readonly" do
    test "render the selection without the hook, the popup or remove controls" do
      for {state, submitted} <- [disabled: %{}, readonly: %{"choice" => ["a", "c"]}] do
        doc = render_combobox([{state, true}, options: ~w(a b c), value: ~w(a c), multiple: true, clearable: true])

        assert attribute(doc, "#choice", "phx-hook") == []
        assert count(doc, "[data-part=popup]") == 0
        assert count(doc, "[data-part=clear]") == 0
        assert count(doc, "template") == 0
        assert count(doc, "[data-part=badge-remove]") == 0
        assert texts(doc, "[data-part=badge-label]") == ["a", "c"]
        assert attribute(doc, "#choice-trigger", "aria-controls") == []
        assert attribute(doc, "[data-part=control]", "class") |> hd() =~ "bg-base-200"
        assert submitted_params(doc) == submitted
      end

      disabled = render_combobox(options: ~w(a), value: "a", disabled: true)
      assert attribute(disabled, "#choice-trigger", "disabled") == [""]
      assert attribute(disabled, "[data-part=anchor]", "disabled") == [""]

      readonly = render_combobox(options: ~w(a), value: "a", readonly: true)
      assert attribute(readonly, "#choice-trigger", "aria-readonly") == ["true"]
      assert attribute(readonly, "#choice-trigger", "disabled") == []
      assert texts(readonly, "[data-part=value-label]") == ["a"]
    end

    test "an interactive combobox has the hook, the popup and an empty trigger" do
      doc = render_combobox(options: ~w(a), label: "Choice")

      assert attribute(doc, "#choice", "phx-hook") == ["BackpexCombobox"]
      assert attribute(doc, "#choice-popup", "popover") == ["manual"]
      assert attribute(doc, "#choice-trigger", "role") == ["combobox"]
      assert attribute(doc, "#choice-trigger", "type") == ["button"]
      assert attribute(doc, "#choice-trigger", "aria-haspopup") == ["listbox"]
      assert attribute(doc, "#choice-trigger", "aria-expanded") == ["false"]
      assert attribute(doc, "#choice-trigger", "aria-controls") == ["choice-listbox"]
      assert attribute(doc, "#choice-trigger", "aria-labelledby") == ["choice-label choice-value"]
      assert attribute(doc, "#choice-label", "for") == ["choice-trigger"]
      assert attribute(doc, "#choice-listbox", "aria-labelledby") == ["choice-label"]
      # No interactive content nested in a button.
      assert count(doc, "button button, button input, button [data-part]") == 0
    end
  end

  describe "search input" do
    test "is shown unless not searchable or below the threshold, except with server search" do
      search? = fn opts -> count(render_combobox([options: ~w(a b c)] ++ opts), "[data-part=search]") == 1 end

      assert search?.([])
      refute search?.(searchable: false)
      assert search?.(search_threshold: 3)
      refute search?.(search_threshold: 4)
      assert search?.(search_threshold: 4, on_search: "search")
      refute search?.(searchable: false, on_search: "search")
    end

    test "has an id but no name, so it is never submitted, and points to the listbox" do
      doc = render_combobox(options: ~w(a))

      assert attribute(doc, "[data-part=search]", "name") == []
      # An id instead, so browsers don't flag a form field without id or name.
      assert attribute(doc, "[data-part=search]", "id") == ["choice-search"]
      assert attribute(doc, "[data-part=search]", "role") == ["combobox"]
      assert attribute(doc, "[data-part=search]", "aria-autocomplete") == ["list"]
      assert attribute(doc, "[data-part=search]", "aria-controls") == ["choice-listbox"]
      assert attribute(doc, "[data-part=search]", "autocomplete") == ["off"]
    end

    test "sets the data attributes of server search only when it is used" do
      doc = render_combobox(options: [], on_search: "search", search_debounce: 50)
      assert attribute(doc, "#choice", "data-on-search") == ["search"]
      assert attribute(doc, "#choice", "data-search-debounce") == ["50"]

      doc = render_combobox(options: [])
      assert attribute(doc, "#choice", "data-on-search") == []
      assert attribute(doc, "#choice", "data-search-debounce") == []
      assert attribute(doc, "#choice", "data-multiple") == []
      assert attribute(doc, "#choice", "data-max") == []
    end
  end

  describe "texts" do
    test "have translated defaults" do
      doc = render_combobox(options: [], multiple: true, clearable: true)

      assert texts(doc, "[data-part=placeholder]") == ["Select options..."]
      assert attribute(doc, "[data-part=search]", "placeholder") == ["Search"]
      assert attribute(doc, "[data-part=search]", "aria-label") == ["Search"]
      assert texts(doc, "[data-part=empty]") == ["No options found"]
      assert attribute(doc, "[data-part=clear]", "aria-label") == ["Clear selection"]
    end

    test "can be overridden, and the empty slot replaces the no results text" do
      doc =
        render_combobox(
          options: [],
          clearable: true,
          placeholder: "Pick one",
          search_placeholder: "Find",
          no_results_text: "Nothing",
          clear_label: "Reset"
        )

      assert texts(doc, "[data-part=placeholder]") == ["Pick one"]
      assert attribute(doc, "[data-part=search]", "placeholder") == ["Find"]
      assert texts(doc, "[data-part=empty]") == ["Nothing"]
      assert attribute(doc, "[data-part=clear]", "aria-label") == ["Reset"]

      doc =
        render_template(fn assigns ->
          ~H"""
          <Combobox.combobox id="c" name="c" options={[]} no_results_text="Nothing">
            <:empty><span id="custom-empty">No match</span></:empty>
            <:header><button id="header-button" type="button">All</button></:header>
            <:footer><button id="footer-button" type="button">More</button></:footer>
          </Combobox.combobox>
          """
        end)

      assert texts(doc, "[data-part=empty]") == ["No match"]
      # The header comes before the listbox and the footer after it, both outside the scrolling listbox.
      popup = doc |> LazyHTML.query("[data-part=popup]") |> LazyHTML.to_html()
      assert [_before_header, after_header] = String.split(popup, ~s(id="header-button"))
      assert [between, _after_footer] = String.split(after_header, ~s(id="footer-button"))
      assert between =~ ~s(data-part="listbox")
      assert count(doc, "[data-part=listbox] button") == 0
    end

    test "the empty state is hidden while there are options" do
      assert attribute(render_combobox(options: ~w(a)), "[data-part=empty]", "hidden") == [""]
      assert attribute(render_combobox(options: []), "[data-part=empty]", "hidden") == []
    end
  end

  describe "attributes" do
    test "maps sizes to full daisyUI class names" do
      for size <- ~w(xs sm md lg xl) do
        doc = render_combobox(options: [], size: size)
        assert attribute(doc, "[data-part=control]", "class") |> hd() =~ "input-#{size}"
      end
    end

    test "scales the badges and the clear button with the size" do
      classes =
        for size <- ~w(xs sm md lg xl) do
          doc = render_combobox(options: ~w(a b), value: ~w(a), multiple: true, clearable: true, size: size)
          [badge] = attribute(doc, "[data-part=badge]", "class")
          [clear] = attribute(doc, "[data-part=clear]", "class")

          badge_size = badge |> String.split() |> Enum.find(&(&1 in ~w(badge-xs badge-sm badge-md badge-lg)))
          clear_size = clear |> String.split() |> Enum.find(&String.starts_with?(&1, "size-"))

          {badge_size, clear_size}
        end

      assert classes == [
               {"badge-xs", "size-4"},
               {"badge-xs", "size-5"},
               {"badge-sm", "size-6"},
               {"badge-md", "size-7"},
               {"badge-lg", "size-8"}
             ]
    end

    test "renders without a name, so the value is not submitted" do
      doc =
        (&Combobox.combobox/1)
        |> render_component(id: "choice", options: ~w(a b), value: "a")
        |> LazyHTML.from_fragment()

      assert attribute(doc, "[data-part=anchor]", "name") == []
      assert texts(doc, "[data-part=value-label]") == ["a"]
      assert submitted_params(doc) == %{}
    end

    test "passes aria attributes to the trigger, form to the inputs and the rest to the root" do
      doc =
        render_combobox(
          options: ~w(a b),
          value: ~w(a),
          multiple: true,
          "aria-label": "Standalone",
          "aria-describedby": "extra",
          "aria-required": "true",
          form: "other-form",
          "phx-target": "3",
          "data-test": "x",
          class: "my-container",
          input_class: "my-input",
          popup_class: "max-h-40"
        )

      assert attribute(doc, "#choice-trigger", "aria-label") == ["Standalone"]
      assert attribute(doc, "#choice-trigger", "aria-labelledby") == ["choice-trigger choice-value"]
      assert attribute(doc, "#choice-trigger", "aria-describedby") == ["extra"]
      assert attribute(doc, "#choice-trigger", "aria-required") == ["true"]
      assert attribute(doc, "#choice-listbox", "aria-label") == ["Standalone"]
      assert attribute(doc, "#choice", "aria-label") == []

      assert attribute(doc, "[data-part=inputs] input", "form") == ["other-form", "other-form"]
      assert attribute(doc, "#choice", "form") == []
      assert attribute(doc, "#choice", "phx-target") == ["3"]
      assert attribute(doc, "#choice", "data-test") == ["x"]

      assert doc |> LazyHTML.query(".my-container > #choice") |> Enum.count() == 1
      control_class = doc |> attribute("[data-part=control]", "class") |> hd()
      assert control_class =~ "my-input"
      refute "input" in String.split(control_class)
      popup_class = doc |> attribute("[data-part=popup]", "class") |> hd()
      assert popup_class =~ "max-h-40"
      refute popup_class =~ "max-h-80"
    end

    test "names the trigger and the listbox by a label outside the combobox" do
      doc = render_combobox(options: ~w(a b), value: "a", "aria-labelledby": "field-label")

      assert attribute(doc, "#choice-trigger", "aria-labelledby") == ["field-label choice-value"]
      assert attribute(doc, "#choice-listbox", "aria-labelledby") == ["field-label"]
      assert count(doc, "#choice-label") == 0
    end

    test "describes the trigger by errors and help text" do
      doc = render_combobox(options: [], errors: ["is wrong"], help_text: "Pick one", label: "L")

      assert attribute(doc, "#choice-trigger", "aria-describedby") == ["choice-errors choice-help"]
      assert texts(doc, "#choice-help") == ["Pick one"]
      assert texts(doc, "#choice-errors") == ["is wrong"]
    end
  end
end
