defmodule DemoWeb.ComboboxLive do
  @moduledoc """
  A showcase of `Backpex.HTML.Combobox.combobox/1`, one section per capability.

  The page is a plain LiveView without a database: all options live in this module. Every section but the validation
  example is a small form that sends `phx-change` to `"change"`, so the server always holds the current params and
  each section shows them next to its control.
  """
  use DemoWeb, :live_view

  import Backpex.HTML.Combobox, only: [combobox: 1]

  alias Backpex.HTML.Layout

  @countries [
    {"Austria", "at"},
    {"Belgium", "be"},
    {"Brazil", "br"},
    {"Canada", "ca"},
    {"Chile", "cl"},
    {"Croatia", "hr"},
    {"Czechia", "cz"},
    {"Denmark", "dk"},
    {"Finland", "fi"},
    {"France", "fr"},
    {"Germany", "de"},
    {"Greece", "gr"},
    {"Iceland", "is"},
    {"India", "in"},
    {"Ireland", "ie"},
    {"Italy", "it"},
    {"Japan", "jp"},
    {"Mexico", "mx"},
    {"Netherlands", "nl"},
    {"New Zealand", "nz"},
    {"Norway", "no"},
    {"Poland", "pl"},
    {"Portugal", "pt"},
    {"Spain", "es"},
    {"Sweden", "se"},
    {"Switzerland", "ch"},
    {"Türkiye", "tr"},
    {"United Kingdom", "gb"},
    {"United States", "us"}
  ]

  # A group is `{group_label, options}`. An option given as a keyword list can be disabled.
  @regions [
    {"Europe", [{"Frankfurt", "eu-central-1"}, {"Ireland", "eu-west-1"}, {"Stockholm", "eu-north-1"}]},
    {"North America", [{"N. Virginia", "us-east-1"}, {"Ohio", "us-east-2"}, {"Oregon", "us-west-2"}]},
    {"Asia Pacific", [{"Tokyo", "ap-northeast-1"}, {"Singapore", "ap-southeast-1"}, {"Sydney", "ap-southeast-2"}]},
    {"South America", [[key: "São Paulo (at capacity)", value: "sa-east-1", disabled: true]]}
  ]

  # Plain strings: the label is the value.
  @topics ~w(Elixir Erlang Phoenix LiveView Ecto Oban Nerves Livebook PostgreSQL Tailwind daisyUI Docker)

  @priorities [
    {"Lowest", "lowest"},
    {"Low", "low"},
    {"Medium", "medium"},
    {"High", "high"},
    {"Highest", "highest"},
    {"Urgent", "urgent"}
  ]

  @sizes ~w(xs sm md lg xl)

  # Maps with `:label` and `:value`; the other keys are available in the `:option` slot.
  @people [
    %{label: "Ada Lovelace", value: "ada", email: "ada@example.com", role: "Engineering"},
    %{label: "Alan Turing", value: "alan", email: "alan@example.com", role: "Research"},
    %{label: "Barbara Liskov", value: "barbara", email: "barbara@example.com", role: "Architecture"},
    %{label: "Edsger Dijkstra", value: "edsger", email: "edsger@example.com", role: "On leave", disabled: true},
    %{label: "Grace Hopper", value: "grace", email: "grace@example.com", role: "Engineering"},
    %{label: "José Valim", value: "jose", email: "jose@example.com", role: "Language design"},
    %{label: "Margaret Hamilton", value: "margaret", email: "margaret@example.com", role: "Flight software"},
    %{label: "Radia Perlman", value: "radia", email: "radia@example.com", role: "Networking"}
  ]

  @languages [
    {"English", "en"},
    {"German", "de"},
    {"French", "fr"},
    {"Spanish", "es"},
    {"Italian", "it"},
    {"Portuguese", "pt"},
    {"Dutch", "nl"},
    {"Polish", "pl"}
  ]

  @teams [{"Platform", "platform"}, {"Product", "product"}, {"Design", "design"}, {"Operations", "operations"}]

  @labels [{"Bug", "bug"}, {"Feature", "feature"}, {"Docs", "docs"}, {"Security", "security"}, {"UX", "ux"}]

  # The in-memory "table" of the server search, as "City, Country" per line.
  @city_lines """
  Aarhus, Denmark
  Abu Dhabi, United Arab Emirates
  Accra, Ghana
  Adelaide, Australia
  Addis Ababa, Ethiopia
  Ahmedabad, India
  Algiers, Algeria
  Almaty, Kazakhstan
  Amman, Jordan
  Amsterdam, Netherlands
  Ankara, Türkiye
  Antwerp, Belgium
  Asunción, Paraguay
  Athens, Greece
  Atlanta, United States
  Auckland, New Zealand
  Austin, United States
  Baghdad, Iraq
  Baku, Azerbaijan
  Bangalore, India
  Bangkok, Thailand
  Barcelona, Spain
  Basel, Switzerland
  Beijing, China
  Beirut, Lebanon
  Belgrade, Serbia
  Bergen, Norway
  Berlin, Germany
  Bern, Switzerland
  Bilbao, Spain
  Birmingham, United Kingdom
  Bogotá, Colombia
  Bologna, Italy
  Bordeaux, France
  Boston, United States
  Bratislava, Slovakia
  Brisbane, Australia
  Bristol, United Kingdom
  Brno, Czechia
  Brussels, Belgium
  Bucharest, Romania
  Budapest, Hungary
  Buenos Aires, Argentina
  Busan, South Korea
  Cairo, Egypt
  Calgary, Canada
  Cape Town, South Africa
  Caracas, Venezuela
  Casablanca, Morocco
  Chengdu, China
  Chennai, India
  Chicago, United States
  Cologne, Germany
  Copenhagen, Denmark
  Córdoba, Argentina
  Cork, Ireland
  Curitiba, Brazil
  Dakar, Senegal
  Dallas, United States
  Da Nang, Vietnam
  Delhi, India
  Denver, United States
  Doha, Qatar
  Dresden, Germany
  Dubai, United Arab Emirates
  Dublin, Ireland
  Dubrovnik, Croatia
  Durban, South Africa
  Düsseldorf, Germany
  Edinburgh, United Kingdom
  Eindhoven, Netherlands
  Espoo, Finland
  Florence, Italy
  Frankfurt, Germany
  Fukuoka, Japan
  Gdańsk, Poland
  Geneva, Switzerland
  Genoa, Italy
  Ghent, Belgium
  Glasgow, United Kingdom
  Gothenburg, Sweden
  Granada, Spain
  Graz, Austria
  Guadalajara, Mexico
  Guangzhou, China
  Hamburg, Germany
  Hanoi, Vietnam
  Hanover, Germany
  Havana, Cuba
  Heidelberg, Germany
  Helsinki, Finland
  Ho Chi Minh City, Vietnam
  Hong Kong, China
  Honolulu, United States
  Houston, United States
  Hyderabad, India
  Innsbruck, Austria
  Istanbul, Türkiye
  Izmir, Türkiye
  Jakarta, Indonesia
  Jerusalem, Israel
  Johannesburg, South Africa
  Kampala, Uganda
  Karachi, Pakistan
  Kathmandu, Nepal
  Kyiv, Ukraine
  Kigali, Rwanda
  Kingston, Jamaica
  Kinshasa, DR Congo
  Kolkata, India
  Kraków, Poland
  Kuala Lumpur, Malaysia
  Kyoto, Japan
  Lagos, Nigeria
  Lahore, Pakistan
  Las Vegas, United States
  Leeds, United Kingdom
  Leipzig, Germany
  Lille, France
  Lima, Peru
  Linz, Austria
  Lisbon, Portugal
  Liverpool, United Kingdom
  Ljubljana, Slovenia
  London, United Kingdom
  Los Angeles, United States
  Luanda, Angola
  Lviv, Ukraine
  Luxembourg, Luxembourg
  Lyon, France
  Madrid, Spain
  Malmö, Sweden
  Manchester, United Kingdom
  Manila, Philippines
  Marrakesh, Morocco
  Marseille, France
  Medellín, Colombia
  Melbourne, Australia
  Mexico City, Mexico
  Miami, United States
  Milan, Italy
  Minneapolis, United States
  Minsk, Belarus
  Montevideo, Uruguay
  Montreal, Canada
  Moscow, Russia
  Mumbai, India
  Munich, Germany
  Muscat, Oman
  Nagoya, Japan
  Nairobi, Kenya
  Nantes, France
  Naples, Italy
  New Orleans, United States
  New York, United States
  Nice, France
  Nuremberg, Germany
  Osaka, Japan
  Oslo, Norway
  Ottawa, Canada
  Oulu, Finland
  Panama City, Panama
  Paris, France
  Perth, Australia
  Philadelphia, United States
  Phnom Penh, Cambodia
  Phoenix, United States
  Porto, Portugal
  Porto Alegre, Brazil
  Portland, United States
  Poznań, Poland
  Prague, Czechia
  Pune, India
  Quebec City, Canada
  Quito, Ecuador
  Recife, Brazil
  Reykjavík, Iceland
  Riga, Latvia
  Rio de Janeiro, Brazil
  Riyadh, Saudi Arabia
  Rome, Italy
  Rotterdam, Netherlands
  Salvador, Brazil
  Salzburg, Austria
  San Diego, United States
  San Francisco, United States
  San José, Costa Rica
  Santiago, Chile
  Santo Domingo, Dominican Republic
  São Paulo, Brazil
  Sapporo, Japan
  Sarajevo, Bosnia and Herzegovina
  Seattle, United States
  Seoul, South Korea
  Seville, Spain
  Shanghai, China
  Shenzhen, China
  Singapore, Singapore
  Sofia, Bulgaria
  Split, Croatia
  Stockholm, Sweden
  Strasbourg, France
  Stuttgart, Germany
  Sydney, Australia
  Taipei, Taiwan
  Tallinn, Estonia
  Tampere, Finland
  Tbilisi, Georgia
  Tel Aviv, Israel
  The Hague, Netherlands
  Thessaloniki, Greece
  Tirana, Albania
  Tokyo, Japan
  Toronto, Canada
  Toulouse, France
  Trondheim, Norway
  Tunis, Tunisia
  Turin, Italy
  Utrecht, Netherlands
  Valencia, Spain
  Valletta, Malta
  Vancouver, Canada
  Venice, Italy
  Vienna, Austria
  Vilnius, Lithuania
  Warsaw, Poland
  Washington, United States
  Wellington, New Zealand
  Wrocław, Poland
  Yerevan, Armenia
  Yokohama, Japan
  Zagreb, Croatia
  Zaragoza, Spain
  Zürich, Switzerland
  """

  @cities @city_lines
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            [city, country] = String.split(line, ", ")
            %{label: city, value: city |> String.downcase() |> String.replace(~r/[^\p{L}]+/u, "-"), country: country}
          end)

  @search_limit 25

  # The params the showcase starts with; disabled comboboxes are not submitted, so theirs never change.
  @initial_params %{
    "topics" => ["Elixir", "LiveView"],
    "size_xs" => ["Elixir"],
    "size_sm" => ["Elixir"],
    "size_md" => ["Elixir"],
    "size_lg" => ["Elixir"],
    "size_xl" => ["Elixir"],
    "cities" => ["lisbon", "kyoto"],
    "disabled_country" => "pt",
    "readonly_country" => "es",
    "readonly_topics" => ["Elixir", "Phoenix"]
  }

  @project_types %{team: :string, labels: {:array, :string}}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> assign(
      countries: @countries,
      regions: @regions,
      topics: @topics,
      priorities: @priorities,
      sizes: @sizes,
      people: @people,
      languages: @languages,
      teams: @teams,
      labels: @labels,
      city_count: length(@cities),
      search_limit: @search_limit,
      city_options: %{"demo_city" => search_cities(""), "demo_cities" => search_cities("")},
      show_modal: false,
      submitted: nil
    )
    |> assign_showcase(@initial_params)
    |> assign(project_params: %{}, project_form: project_form(%{}))
    |> then(&{:ok, &1})
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.admin
      socket={@socket}
      flash={@flash}
      current_url={@current_url}
      current_theme={@current_theme}
      sidebar_open={@sidebar_open}
      sidebar_section_states={@sidebar_section_states}
      preferences_manifest={@preferences_manifest}
    >
      <div class="max-w-5xl space-y-6 pb-12">
        <div>
          <Layout.main_title>Combobox</Layout.main_title>
          <p class="text-base-content/70 max-w-3xl">
            A select with search, multiple selection, groups and custom option markup. Use it with the mouse or the
            keyboard: <kbd class="kbd kbd-sm">↑</kbd> <kbd class="kbd kbd-sm">↓</kbd>
            move, <kbd class="kbd kbd-sm">Enter</kbd>
            selects, <kbd class="kbd kbd-sm">Esc</kbd>
            closes and <kbd class="kbd kbd-sm">Backspace</kbd>
            on a closed combobox removes the last value.
          </p>
        </div>

        <.example id="basic" title="Single select" values={[{"country", @params["country"]}]}>
          <:description>
            The default: one value, with a search input in the popup that filters the options in the browser,
            ignoring case and accents. The server only receives the value through <code>phx-change</code>.
          </:description>
          <.form for={@form} id="basic-form" phx-change="change">
            <.combobox
              field={@form[:country]}
              label="Country"
              options={@countries}
              placeholder="Choose a country"
              help_text="Try typing “tur” to find Türkiye."
            />
          </.form>
        </.example>

        <.example id="grouped" title="Groups and disabled options" values={[{"region", @params["region"]}]}>
          <:description>
            Options are grouped under a heading with <code>{"{group_label, options}"}</code>; search hides groups
            without a match. São Paulo is disabled: it can be seen but not selected, and the keyboard skips it.
            The clear button removes the value.
          </:description>
          <.form for={@form} id="grouped-form" phx-change="change">
            <.combobox
              field={@form[:region]}
              label="Deployment region"
              options={@regions}
              placeholder="Choose a region"
              clearable
            />
          </.form>
        </.example>

        <.example id="multiple" title="Multiple with a maximum" values={[{"topics", @params["topics"]}]}>
          <:description>
            <code>multiple</code> toggles options and shows the selection as badges. With <code>max={"{3}"}</code>, the
            other options are disabled once three are selected. <code>clearable</code> removes all of them. With
            nothing selected the form still sends the field, as an empty string.
          </:description>
          <.form for={@form} id="multiple-form" phx-change="change">
            <.combobox
              field={@form[:topics]}
              label="Topics"
              options={@topics}
              placeholder="Up to three topics"
              multiple
              max={3}
              clearable
            />
          </.form>
        </.example>

        <.example id="typeahead" title="Without search" values={[{"priority", @params["priority"]}]}>
          <:description>
            <code>searchable={"{false}"}</code> leaves out the search input, like a native select. Typeahead still works:
            focus the combobox and type “h” to jump to High, then “h” again for Highest.
          </:description>
          <.form for={@form} id="typeahead-form" phx-change="change">
            <.combobox
              field={@form[:priority]}
              label="Priority"
              options={@priorities}
              placeholder="Choose a priority"
              searchable={false}
            />
          </.form>
        </.example>

        <.example
          id="sizes"
          title="Sizes"
          values={for size <- @sizes, do: {"size_#{size}", @params["size_#{size}"]}}
        >
          <:description>
            <code>size</code>
            scales the control, the badges, the search input and the options together, from <code>xs</code>
            to <code>xl</code>.
          </:description>
          <.form for={@form} id="sizes-form" phx-change="change" class="space-y-3">
            <.combobox
              :for={size <- @sizes}
              field={@form[:"size_#{size}"]}
              label={"Size #{size}"}
              options={@topics}
              size={size}
              multiple
              clearable
            />
          </.form>
        </.example>

        <.example id="custom-option" title="Custom option markup" values={[{"assignee", @params["assignee"]}]}>
          <:description>
            The <code>:option</code>
            slot receives each option as a map, including extra keys like <code>:email</code>. The selected value shows the label. The
            <code>:empty</code>
            slot replaces the text
            shown when nothing matches; try “xyz”.
          </:description>
          <.form for={@form} id="custom-option-form" phx-change="change">
            <.combobox
              field={@form[:assignee]}
              label="Assignee"
              options={@people}
              placeholder="Assign someone"
              search_placeholder="Search by name"
              clearable
            >
              <:option :let={person}>
                <div class="flex items-center gap-3">
                  <div class="avatar avatar-placeholder" aria-hidden="true">
                    <div class="bg-neutral text-neutral-content w-8 rounded-full">
                      <span class="text-xs">{initials(person.label)}</span>
                    </div>
                  </div>
                  <div class="min-w-0">
                    <div class="truncate font-medium">{person.label}</div>
                    <div class="text-base-content/70 truncate text-xs">{person.email} · {person.role}</div>
                  </div>
                </div>
              </:option>
              <:empty>Nobody on the team matches your search.</:empty>
            </.combobox>
          </.form>
        </.example>

        <.example
          id="server-search"
          title="Server search"
          values={[{"city", @params["city"]}, {"cities", @params["cities"]}]}
        >
          <:description>
            With <code>on_search</code>, the combobox pushes the query to the server, which renders the matches
            from {@city_count} cities. Pass the options of the current value in <code>selected_options</code>, so
            their labels show even when the search results do not contain them.
          </:description>
          <.form for={@form} id="server-search-form" phx-change="change" class="space-y-3">
            <.combobox
              field={@form[:city]}
              label="City"
              options={@city_options["demo_city"]}
              selected_options={cities_by_value(@params["city"])}
              on_search="search-cities"
              placeholder="Search for a city"
              clearable
            >
              <:option :let={city}>
                <span class="block">{city.label}</span>
                <span class="text-base-content/70 block text-xs">{city.country}</span>
              </:option>
              <:footer>
                <p class="text-base-content/70 text-xs">Shows at most {@search_limit} matches.</p>
              </:footer>
            </.combobox>
            <.combobox
              field={@form[:cities]}
              label="Cities to visit"
              options={@city_options["demo_cities"]}
              selected_options={cities_by_value(@params["cities"])}
              on_search="search-cities"
              placeholder="Search for cities"
              multiple
              clearable
            />
          </.form>
        </.example>

        <.example id="header-footer" title="Header, footer and commands" values={[{"languages", @params["languages"]}]}>
          <:description>
            The <code>:header</code> and <code>:footer</code> slots stay pinned around the options. Their buttons
            dispatch <code>combobox:select-all</code> and <code>combobox:clear</code> with <code>JS.dispatch</code>;
            “Select all” selects what the search currently shows. Other elements can send the same commands,
            like the button below.
          </:description>
          <.form for={@form} id="header-footer-form" phx-change="change" class="space-y-3">
            <.combobox
              field={@form[:languages]}
              label="Languages"
              options={@languages}
              placeholder="Choose languages"
              multiple
            >
              <:header>
                <button type="button" class="btn btn-ghost btn-xs" phx-click={JS.dispatch("combobox:select-all")}>
                  Select all
                </button>
              </:header>
              <:footer>
                <button type="button" class="btn btn-ghost btn-xs" phx-click={JS.dispatch("combobox:clear")}>
                  Clear
                </button>
              </:footer>
            </.combobox>
            <button
              id="open-languages"
              type="button"
              class="btn btn-sm"
              phx-click={JS.dispatch("combobox:open", to: "#demo_languages")}
            >
              Open the combobox
            </button>
          </.form>
        </.example>

        <.example
          id="disabled-readonly"
          title="Disabled and readonly"
          values={[
            {"disabled_country", @params["disabled_country"]},
            {"readonly_country", @params["readonly_country"]},
            {"readonly_topics", @params["readonly_topics"]}
          ]}
        >
          <:description>
            Neither can be opened. A <code>disabled</code> combobox is not submitted, so its value here is the one
            the page started with. A <code>readonly</code> combobox looks like a readonly input and is submitted.
          </:description>
          <.form for={@form} id="disabled-readonly-form" phx-change="change" class="space-y-3">
            <.combobox field={@form[:disabled_country]} label="Disabled" options={@countries} disabled />
            <.combobox field={@form[:readonly_country]} label="Readonly" options={@countries} readonly />
            <.combobox
              field={@form[:readonly_topics]}
              label="Readonly, multiple"
              options={@topics}
              multiple
              readonly
            />
          </.form>
        </.example>

        <.example
          id="validation"
          title="Validation"
          values={[{"team", @project_params["team"]}, {"labels", @project_params["labels"]}]}
        >
          <:description>
            With <code>field</code>, errors of the changeset show once the user changed the combobox, not before.
            Both fields are required, and a project needs at least two labels. Submit to see the params the server
            receives.
          </:description>
          <.form for={@project_form} id="project-form" phx-change="validate-project" phx-submit="save-project">
            <div class="space-y-3">
              <.combobox field={@project_form[:team]} label="Team" options={@teams} placeholder="Choose a team" />
              <.combobox
                field={@project_form[:labels]}
                label="Labels"
                options={@labels}
                placeholder="Choose two to four labels"
                help_text="At least two, at most four."
                multiple
                max={4}
              />
            </div>
            <button id="project-submit" type="submit" class="btn btn-primary btn-sm mt-4">Create project</button>
          </.form>
          <div :if={@submitted} id="project-submitted" class="space-y-2">
            <div role="status" class={["alert", if(@submitted.valid?, do: "alert-success", else: "alert-error")]}>
              {if @submitted.valid?, do: "The project is valid.", else: "The project has errors."}
            </div>
            <p class="text-sm font-semibold">Submitted params</p>
            <pre class="bg-base-200 rounded-box overflow-x-auto p-3 text-xs">{inspect(@submitted.params, pretty: true)}</pre>
          </div>
        </.example>

        <.example id="modal" title="Inside a modal" values={[{"modal_country", @params["modal_country"]}]}>
          <:description>
            The popup opens in the browser's top layer, so a modal, a table or any container with hidden overflow
            does not clip it.
          </:description>
          <button id="open-modal" type="button" class="btn btn-sm" phx-click="open-modal">Open the modal</button>
          <Layout.modal
            :if={@show_modal}
            id="combobox-modal"
            title="Ship to"
            on_cancel={JS.push("close-modal") |> JS.focus(to: "#open-modal")}
          >
            <.form for={@form} id="modal-form" phx-change="change" class="space-y-4 p-5">
              <.combobox
                field={@form[:modal_country]}
                label="Country"
                options={@countries}
                placeholder="Choose a country"
              />
              <p class="text-base-content/70 text-sm">
                Server value: <code>{inspect(@params["modal_country"])}</code>
              </p>
            </.form>
          </Layout.modal>
        </.example>
      </div>
    </Layouts.admin>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :values, :list, required: true, doc: "`{name, value}` pairs of the params the server holds"
  slot :description, required: true
  slot :inner_block, required: true

  defp example(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-title"} class="card card-border bg-base-100">
      <div class="card-body grid gap-6 lg:grid-cols-[minmax(0,1fr)_16rem]">
        <div class="min-w-0 space-y-4">
          <div>
            <h2 id={"#{@id}-title"} class="card-title">{@title}</h2>
            <p class="text-base-content/70 mt-1 text-sm">{render_slot(@description)}</p>
          </div>
          {render_slot(@inner_block)}
        </div>
        <div id={"#{@id}-values"} class="bg-base-200 rounded-box self-start p-3 text-sm">
          <p class="text-base-content/70 mb-2 text-xs font-semibold uppercase">Server value</p>
          <dl class="grid gap-x-4 gap-y-1 sm:grid-cols-2 lg:grid-cols-1">
            <div :for={{name, value} <- @values}>
              <dt class="text-base-content/70 text-xs">{name}</dt>
              <dd class="break-words font-mono">{inspect(value)}</dd>
            </div>
          </dl>
        </div>
      </div>
    </section>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("change", %{"demo" => params}, socket) do
    {:noreply, assign_showcase(socket, Map.merge(socket.assigns.params, params))}
  end

  # `id` is the DOM id of the combobox that searched, so both server search comboboxes keep their own results.
  def handle_event("search-cities", %{"query" => query, "id" => id}, socket) do
    {:noreply, update(socket, :city_options, &Map.put(&1, id, search_cities(query)))}
  end

  def handle_event("validate-project", %{"project" => params}, socket) do
    form = params |> project_changeset() |> Map.put(:action, :validate) |> to_form(as: :project)
    {:noreply, assign(socket, project_params: params, project_form: form)}
  end

  def handle_event("save-project", %{"project" => params}, socket) do
    changeset = project_changeset(params)

    socket
    |> assign(project_params: params, project_form: changeset |> Map.put(:action, :insert) |> to_form(as: :project))
    |> assign(:submitted, %{params: params, valid?: changeset.valid?})
    |> then(&{:noreply, &1})
  end

  def handle_event("open-modal", _params, socket), do: {:noreply, assign(socket, :show_modal, true)}
  def handle_event("close-modal", _params, socket), do: {:noreply, assign(socket, :show_modal, false)}

  # The showcase keeps the raw params: they are exactly what the comboboxes submit.
  defp assign_showcase(socket, params) do
    assign(socket, params: params, form: to_form(params, as: :demo))
  end

  defp project_form(params), do: params |> project_changeset() |> to_form(as: :project)

  defp project_changeset(params) do
    {%{}, @project_types}
    |> Ecto.Changeset.cast(params, Map.keys(@project_types))
    |> Ecto.Changeset.validate_required([:team, :labels])
    |> Ecto.Changeset.validate_length(:labels, min: 2, max: 4)
  end

  defp search_cities(query) do
    query = normalize(query)

    @cities
    |> Enum.filter(&(&1.label |> normalize() |> String.contains?(query)))
    |> Enum.take(@search_limit)
  end

  defp cities_by_value(value) do
    values = List.wrap(value)
    Enum.filter(@cities, &(&1.value in values))
  end

  # Case and accent insensitive, like the search in the browser: "zur" finds "Zürich".
  defp normalize(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end

  defp initials(name) do
    name
    |> String.split()
    |> Enum.map_join(&String.first/1)
  end
end
