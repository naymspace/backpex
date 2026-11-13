defmodule Backpex.Test.ComboboxLive do
  @moduledoc """
  A plain LiveView with one `Backpex.HTML.Combobox.combobox/1` per variant, for the browser tests of the combobox.

  All comboboxes but the `standalone` one belong to the form `#combobox-form`. It validates on `phx-change` and renders
  the last params of `phx-change` and submit as JSON into `#last-change` and `#last-submit`. The `country` field is
  required. `#patch-button` patches the page without touching the form, and `#server-patch` patches it from the server
  after 300 ms, so tests can patch while a popup is open. `#changes` counts the `phx-change` events.

  The server overrules the admin's choice in `restricted` and `restricted_tags`, as a `phx-change` handler that drops
  an invalid value would: it keeps the previous value instead of `"rejected"` and replaces `"other"` with `"allowed"`.
  `blur_choice` has `phx-debounce="blur"`. `Backpex.Test.ComboboxSearchComponent` handles the server search of its
  combobox itself (`phx-target`).
  """
  use Phoenix.LiveView

  import Backpex.HTML.Combobox

  alias Phoenix.LiveView.JS

  @types %{
    country: :string,
    fruit: :string,
    tags: {:array, :string},
    size: :string,
    priority: :string,
    user: :string,
    person: :string,
    people: {:array, :string},
    languages: {:array, :string},
    disabled_choice: :string,
    readonly_choice: :string,
    readonly_tags: {:array, :string},
    dialog_choice: :string,
    bottom_choice: :string,
    restricted: :string,
    restricted_tags: {:array, :string},
    native_restricted: :string,
    long_tags: {:array, :string},
    all_tags: {:array, :string},
    blur_choice: :string
  }

  @defaults %{
    "readonly_choice" => "b",
    "readonly_tags" => ["a", "c"]
  }

  @countries [
    {"Germany", "de"},
    {"Austria", "at"},
    {"Switzerland", "ch"},
    {"France", "fr"},
    {"Belgium", "be"},
    {"Netherlands", "nl"},
    {"Denmark", "dk"},
    {"Sweden", "se"},
    {"Norway", "no"},
    {"Finland", "fi"},
    {"Iceland", "is"},
    {"Ireland", "ie"},
    {"Portugal", "pt"},
    {"Spain", "es"},
    {"Italy", "it"},
    {"Poland", "pl"},
    {"Czechia", "cz"},
    {"Hungary", "hu"},
    {"Croatia", "hr"},
    {"Greece", "gr"},
    {"Türkiye", "tr"}
  ]

  @fruits [
    {"Citrus", [{"Lemon", "lemon"}, {"Orange", "orange"}, {"Lime", "lime"}]},
    {"Berries", [{"Strawberry", "strawberry"}, [key: "Blueberry", value: "blueberry", disabled: true], "Raspberry"]},
    {"Stone fruit", [{"Peach", "peach"}, {"Cherry", "cherry"}]}
  ]

  @tags ~w(Elixir Erlang Phoenix LiveView Ecto Tailwind daisyUI)

  @sizes [{"Small", "s"}, {"Medium", "m"}, {"Large", "l"}]

  @priorities [{"Low", "low"}, {"Medium", "medium"}, {"High", "high"}, {"Highest", "highest"}, {"Urgent", "urgent"}]

  @users [
    %{label: "Ada Lovelace", value: "ada", email: "ada@example.com"},
    %{label: "Grace Hopper", value: "grace", email: "grace@example.com"},
    %{label: "Alan Turing", value: "alan", email: "alan@example.com"},
    %{label: "Edsger Dijkstra", value: "edsger", email: "edsger@example.com", disabled: true}
  ]

  # The in-memory "database" of the server search.
  @people Enum.map(
            ~w(Ada Alan Barbara Brian Charles Claude Dennis Donald Edsger Frances Grace Guido Ivan James Jean Joe John
               Ken Leslie Linus Margaret Niklaus René Richard Rob Robin Tim Tony Ward Yukihiro),
            &%{label: &1, value: String.downcase(&1)}
          )

  @search_limit 8

  @languages [{"English", "en"}, {"German", "de"}, {"French", "fr"}, {"Spanish", "es"}, {"Italian", "it"}]

  @simple [{"Option A", "a"}, {"Option B", "b"}, {"Option C", "c"}]

  # "al" matches Alpha and Alabama; Delta is disabled, so "select all" leaves it out.
  @all_tags [
    {"Alpha", "alpha"},
    {"Beta", "beta"},
    {"Gamma", "gamma"},
    [key: "Delta", value: "delta", disabled: true],
    {"Alabama", "alabama"}
  ]

  @restricted [{"Allowed", "allowed"}, {"Rejected", "rejected"}, {"Other", "other"}]

  @long_tags Enum.map(1..30, &{"Item #{String.pad_leading(to_string(&1), 2, "0")}", "item-#{&1}"})

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> assign(
      countries: @countries,
      fruits: @fruits,
      tags: @tags,
      sizes: @sizes,
      priorities: @priorities,
      users: @users,
      languages: @languages,
      simple: @simple,
      restricted: @restricted,
      long_tags: @long_tags,
      all_tags: @all_tags,
      changes: 0,
      people_options: search_people(""),
      people_query: "",
      show_modal: false,
      search_events: 0,
      patches: 0,
      last_change: nil,
      last_submit: nil
    )
    |> assign_form(@defaults, false)
    |> then(&{:ok, &1})
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Backpex.Test.Layouts.admin
      socket={@socket}
      current_url={@current_url}
      flash={@flash}
      current_theme={@current_theme}
      sidebar_open={@sidebar_open}
      sidebar_section_states={@sidebar_section_states}
      preferences_manifest={@preferences_manifest}
    >
      <div class="space-y-6 pb-6">
        <h1 class="text-2xl font-semibold">Combobox</h1>

        <div class="flex flex-wrap gap-2">
          <button id="patch-button" type="button" class="btn btn-sm" phx-click="patch">Patch</button>
          <button id="server-patch-button" type="button" class="btn btn-sm" phx-click="server-patch">
            Patch in 300 ms
          </button>
          <button
            id="open-tags"
            type="button"
            class="btn btn-sm"
            phx-click={JS.dispatch("combobox:open", to: "#combobox_tags")}
          >
            Open tags
          </button>
          <button
            id="close-tags"
            type="button"
            class="btn btn-sm"
            phx-click={JS.dispatch("combobox:close", to: "#combobox_tags")}
          >
            Close tags
          </button>
          <button
            id="clear-tags"
            type="button"
            class="btn btn-sm"
            phx-click={JS.dispatch("combobox:clear", to: "#combobox_tags")}
          >
            Clear tags
          </button>
          <span id="patches">Patches: {@patches}</span>
          <span id="changes">Changes: {@changes}</span>
        </div>

        <.form for={@form} id="combobox-form" phx-change="validate" phx-submit="save" class="grid gap-4 md:grid-cols-2">
          <.combobox field={@form[:country]} label="Country" options={@countries} help_text="Required" clearable />

          <.combobox field={@form[:fruit]} label="Fruit" options={@fruits} clearable />

          <.combobox field={@form[:tags]} label="Tags" options={@tags} multiple max={3} clearable />

          <.combobox field={@form[:size]} label="Size" options={@sizes} clearable searchable={false} size="sm" />

          <.combobox field={@form[:priority]} label="Priority" options={@priorities} searchable={false} />

          <.combobox field={@form[:user]} label="User" options={@users} placeholder="Pick a user">
            <:option :let={user}>
              <span class="block font-medium">{user.label}</span>
              <span data-email class="text-base-content/60 block text-xs">{user.email}</span>
            </:option>
            <:empty>No user matches</:empty>
          </.combobox>

          <.combobox
            field={@form[:person]}
            label="Person (server search)"
            options={@people_options}
            selected_options={selected_people(@form[:person].value)}
            on_search="search-people"
            search_debounce={100}
            clearable
          />

          <.combobox
            field={@form[:people]}
            label="People (server search, multiple)"
            options={@people_options}
            selected_options={selected_people(@form[:people].value)}
            on_search="search-people"
            search_debounce={100}
            multiple
          />

          <.combobox field={@form[:languages]} label="Languages" options={@languages} multiple>
            <:header>
              <button
                id="languages-select-all"
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click={JS.dispatch("combobox:select-all")}
              >
                Select all
              </button>
            </:header>
            <:footer>
              <button
                id="languages-clear"
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click={JS.dispatch("combobox:clear")}
              >
                Clear
              </button>
            </:footer>
          </.combobox>

          <%!-- A disabled input is not submitted, so the value comes from the template, not the params. --%>
          <.combobox field={@form[:disabled_choice]} label="Disabled" options={@simple} value="b" disabled />

          <.combobox field={@form[:readonly_choice]} label="Readonly" options={@simple} readonly />

          <.combobox field={@form[:readonly_tags]} label="Readonly tags" options={@simple} multiple readonly />

          <div>
            <%!-- showModal() puts the dialog in the top layer and makes the rest of the page inert. --%>
            <button
              id="open-dialog"
              type="button"
              class="btn btn-sm"
              onclick="document.getElementById('combobox-dialog').showModal()"
            >
              Open dialog
            </button>
            <%!-- A dialog inside the form keeps its combobox part of the form. --%>
            <%!-- Patches must not remove the `open` attribute that showModal() set. --%>
            <dialog
              id="combobox-dialog"
              class="modal"
              aria-labelledby="combobox-dialog-title"
              phx-mounted={JS.ignore_attributes(["open"])}
            >
              <div class="modal-box overflow-visible">
                <h2 id="combobox-dialog-title" class="mb-2 text-lg font-semibold">Dialog</h2>
                <.combobox field={@form[:dialog_choice]} label="Dialog choice" options={@countries} />
                <div class="modal-action">
                  <button
                    id="close-dialog"
                    type="button"
                    class="btn btn-sm"
                    onclick="document.getElementById('combobox-dialog').close()"
                  >
                    Close
                  </button>
                </div>
              </div>
            </dialog>
          </div>

          <.combobox field={@form[:restricted]} label="Restricted" options={@restricted} clearable />

          <.combobox field={@form[:restricted_tags]} label="Restricted tags" options={@restricted} multiple />

          <%!-- A native select overruled the same way, to compare the combobox with. --%>
          <fieldset class="fieldset py-0">
            <label for="native-restricted" class="label mb-1">Native restricted</label>
            <select id="native-restricted" name={@form[:native_restricted].name} class="select w-full">
              {Phoenix.HTML.Form.options_for_select([{"None", ""} | @restricted], @form[:native_restricted].value)}
            </select>
          </fieldset>

          <.combobox field={@form[:long_tags]} label="Long tags" options={@long_tags} multiple />

          <.combobox field={@form[:all_tags]} label="All tags" options={@all_tags} multiple select_all />

          <div class="md:col-span-2">
            <button id="submit-button" type="submit" class="btn btn-primary btn-sm">Submit</button>
          </div>

          <%!-- Pushes the last combobox to the bottom of a page taller than the viewport. --%>
          <div class="h-[150vh] md:col-span-2" aria-hidden="true"></div>

          <.combobox field={@form[:blur_choice]} label="Blur choice" options={@simple} phx-debounce="blur" />

          <.combobox field={@form[:bottom_choice]} label="Bottom choice" options={@countries} class="md:col-span-2" />
        </.form>

        <.combobox
          id="standalone"
          name="standalone"
          value="b"
          options={@simple}
          aria-label="Standalone"
        />

        <.live_component module={Backpex.Test.ComboboxSearchComponent} id="search-component" />

        <div id="sizes" class="grid gap-2 md:grid-cols-5">
          <.combobox
            :for={size <- ~w(xs sm md lg xl)}
            id={"size-#{size}"}
            name={"size_#{size}"}
            value="a"
            options={@simple}
            size={size}
            clearable
            aria-label={"Size #{size}"}
          />
        </div>

        <button id="open-modal" type="button" class="btn btn-sm" phx-click="open-modal">Open Backpex modal</button>
        <%!-- The Backpex modal closes on Escape through a window keydown listener. --%>
        <Backpex.HTML.Layout.modal
          :if={@show_modal}
          id="backpex-modal"
          title="Backpex modal"
          on_cancel={JS.push("close-modal")}
        >
          <div class="p-5">
            <.combobox id="modal-choice" name="modal_choice" value="" label="Modal choice" options={@countries} />
          </div>
        </Backpex.HTML.Layout.modal>

        <div class="grid gap-2 md:grid-cols-2">
          <pre id="last-change" class="bg-base-200 whitespace-pre-wrap break-all p-2 text-xs">{json(@last_change)}</pre>
          <pre id="last-submit" class="bg-base-200 whitespace-pre-wrap break-all p-2 text-xs">{json(@last_submit)}</pre>
          <pre id="search-events" class="bg-base-200 p-2 text-xs">{@search_events}</pre>
          <pre id="people-query" class="bg-base-200 p-2 text-xs">{@people_query}</pre>
        </div>
      </div>
    </Backpex.Test.Layouts.admin>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"combobox" => params} = all_params, socket) do
    socket
    |> assign(:last_change, all_params)
    |> update(:changes, &(&1 + 1))
    |> assign_form(overrule(params, socket.assigns.form), true)
    |> then(&{:noreply, &1})
  end

  def handle_event("save", %{"combobox" => params} = all_params, socket) do
    socket
    |> assign(:last_submit, all_params)
    |> assign_form(params, true)
    |> then(&{:noreply, &1})
  end

  def handle_event("search-people", %{"query" => query, "id" => _id}, socket) do
    socket
    |> assign(people_options: search_people(query), people_query: query)
    |> update(:search_events, &(&1 + 1))
    |> then(&{:noreply, &1})
  end

  def handle_event("open-modal", _params, socket), do: {:noreply, assign(socket, :show_modal, true)}
  def handle_event("close-modal", _params, socket), do: {:noreply, assign(socket, :show_modal, false)}

  def handle_event("patch", _params, socket), do: {:noreply, update(socket, :patches, &(&1 + 1))}

  def handle_event("server-patch", _params, socket) do
    Process.send_after(self(), :patch, 300)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(:patch, socket), do: {:noreply, update(socket, :patches, &(&1 + 1))}

  defp assign_form(socket, params, validate?) do
    changeset =
      {%{}, @types}
      |> Ecto.Changeset.cast(params, Map.keys(@types))
      |> Ecto.Changeset.validate_required([:country])

    changeset = if validate?, do: Map.put(changeset, :action, :validate), else: changeset

    assign(socket, :form, Phoenix.Component.to_form(changeset, as: :combobox))
  end

  defp overrule(params, form) do
    params
    |> Map.replace_lazy("restricted", fn
      "rejected" -> form[:restricted].value || ""
      "other" -> "allowed"
      value -> value
    end)
    |> Map.replace_lazy("native_restricted", fn
      "rejected" -> form[:native_restricted].value || ""
      value -> value
    end)
    |> Map.replace_lazy("restricted_tags", fn
      values when is_list(values) ->
        values |> List.delete("rejected") |> Enum.map(&if(&1 == "other", do: "allowed", else: &1)) |> Enum.uniq()

      value ->
        value
    end)
  end

  defp search_people(query) do
    query = String.downcase(query)

    @people
    |> Enum.filter(&(&1.label |> String.downcase() |> String.contains?(query)))
    |> Enum.take(@search_limit)
  end

  defp selected_people(value) do
    values = value |> List.wrap() |> Enum.map(&to_string/1)
    Enum.filter(@people, &(&1.value in values))
  end

  defp json(nil), do: ""
  defp json(params), do: Phoenix.json_library().encode!(params)
end
