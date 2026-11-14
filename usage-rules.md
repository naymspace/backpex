# Backpex usage rules

Backpex builds admin panels in Phoenix LiveView apps. A LiveResource module configures the index, show and form views of one Ecto schema; fields, filters, actions and metrics are modules implementing Backpex behaviours. Docs and guides of the released version: https://hexdocs.pm/backpex (https://hexdocs.pm/backpex/llms.txt lists every guide as Markdown). Read the guide of the area you work in; the module docs list every option.

## Setup

- `mix igniter.install backpex` (or `mix backpex.install` once the dependency is added) runs the steps of the [installation guide](https://hexdocs.pm/backpex/installation.html), except the `LiveSocket` params: set those yourself.
- `app.js`: `import { Hooks as BackpexHooks, backpexParams } from 'backpex'`, then `new LiveSocket('/live', Socket, { params: backpexParams({ _csrf_token: csrfToken }), hooks: { ...Hooks, ...BackpexHooks } })`. `backpexParams` takes a params object; for params computed in a function, merge `BackpexPreferences.connectParams()` into its result.
- Styles need Tailwind CSS 4 and daisyUI 5, with `@source "../../deps/backpex/**/*.*ex";` and `@source "../../deps/backpex/assets/js/**/*.*js";` in the stylesheet. `@tailwindcss/forms` conflicts with daisyUI.
- `config :backpex, :pubsub_server, MyApp.PubSub`, and `import_deps: [:backpex]` in `.formatter.exs`.

## Routing

```elixir
import Backpex.Router

scope "/admin", MyAppWeb do
  pipe_through [:browser, :require_admin]

  backpex_routes()

  live_session :admin, on_mount: Backpex.InitAssigns do
    live_resources "/posts", PostLive
    live_resources "/categories", CategoryLive, only: [:index, :show]
  end
end
```

- `backpex_routes/0` adds the preferences endpoint: once per scope, behind the same authentication plugs as the LiveResources.
- `Backpex.InitAssigns` assigns `@current_url` and the preference assigns the layout reads. `live_resources/3` takes `only:` and `except:` with `:index`, `:new`, `:edit`, `:show`.

## LiveResource

```elixir
defmodule MyAppWeb.PostLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: MyApp.Blog.Post,
      repo: MyApp.Repo,
      update_changeset: &MyApp.Blog.Post.update_changeset/3,
      create_changeset: &MyApp.Blog.Post.create_changeset/3
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {MyAppWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Post"

  @impl Backpex.LiveResource
  def plural_name, do: "Posts"

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{module: Backpex.Fields.Text, label: "Title", searchable: true},
      category: %{
        module: Backpex.Fields.BelongsTo,
        label: "Category",
        display_field: :name,
        live_resource: MyAppWeb.CategoryLive
      }
    ]
  end
end
```

- Return the layout from `c:Backpex.LiveResource.layout/1`; the `layout:` option is deprecated. The layout wraps its content in `Backpex.HTML.Layout.app_shell/1` and renders `Backpex.HTML.Layout.flash_messages/1`.
- `singular_name/0` and `plural_name/0` have no default. Every other callback has one: `fields/0`, `filters/0` (or `filters/1` with assigns), `panels/0`, `metrics/0`, `item_actions/1`, `resource_actions/0`, `can?/3`, the `on_item_*` hooks, `return_to/5`, `render_resource_slot/3`, `translate/1`.
- The options of `use Backpex.LiveResource` (`primary_key`, `init_order`, `per_page_default`, `full_text_search`, `fluid?`, `persist`, `context_assigns`, …) are validated against the schema in the `Backpex.LiveResource` docs. Set `primary_key:` when the key is not `:id`; Backpex supports one primary key column, not compound keys.
- `adapter_config` belongs to `Backpex.Adapters.Ecto`: `schema` and `repo` are required; the changeset functions take `(item, attrs, metadata)`, where `metadata` holds `:assigns` and `:target`; `item_query` takes `(query, live_action, assigns)` and builds on the given query (`from p in query, where: ...`).

## Fields

- `fields/0` returns a keyword list of `name: %{module: Backpex.Fields.<Type>, label: "..."}`. Built-in types: `Text`, `Textarea`, `Number`, `Currency`, `Email`, `URL`, `Boolean`, `Date`, `DateTime`, `Time`, `Select`, `MultiSelect`, `Checkgroup`, `Upload`, `BelongsTo`, `HasMany`, `HasManyThrough`, `InlineCRUD`.
- Options shared by all fields are in `Backpex.Field` (e.g. `searchable`, `orderable`, `only`/`except` with `:new`, `:edit`, `:show`, `:index`, `visible`, `can?`, `readonly`, `panel`, `index_editable`, `select` for computed values, `help_text`, `default`); options of a type are in its module docs. An unknown or mistyped option raises with the field and LiveResource name.
- A custom field does `use Backpex.Field, config_schema: @config_schema` with a NimbleOptions schema and implements `render_value/1` and `render_form/1` ([custom fields guide](https://hexdocs.pm/backpex/custom-fields.html)). The form passes only the params of the fields an admin may edit to the changeset; a field whose form submits params under other names than its own returns them from `param_keys/2`.

## Filters, actions and metrics

- `filters/0` returns `field_name: %{module: Backpex.Filters.Select, label: "Status", options: [{"Open", "open"}, {"Closed", "closed"}]}`: filters are configured like fields, with a built-in module and its options, and need no module of their own ([filter guide](https://hexdocs.pm/backpex/how-to-add-a-filter.html)). Built-ins: `Backpex.Filters.Boolean` (`options`: maps with `label`, `key` and a `predicate`, a `Backpex.Expr` expression such as `expr(published == true)`), `Backpex.Filters.Select` and `Backpex.Filters.MultiSelect` (`options`: `{label, value}` tuples; `prompt`), `Backpex.Filters.Range` (`type`: `:number`, `:date` or `:datetime`); `options` and `prompt` also take a function that receives the assigns. Every filter takes `label` (required unless the module implements `label/0`), `default`, `presets`, `can?` and `condition`; an unknown or invalid option raises with the filter and LiveResource name. Add `import Backpex.Expr, only: [expr: 1]` to the LiveResource to write expressions there.
- Filters don't build queries: the adapter turns their expression into one. `condition: fn {field, _config}, value, _assigns -> expr(ref(^field) >= ^value) end` changes which items a single filter keeps (`nil` keeps all). A module with `use Backpex.Filters.Select` (or another built-in) is only needed to reuse a filter: its callbacks (`options/1`, `prompt/0`, `type/0` of Range, `label/0`) are the defaults of the options. A custom filter does `use BackpexWeb, :filter` and `use Backpex.Filter, config_schema: [...]` and implements `condition/3`, `render/1` and `render_form/1`, optionally `type/2` and `changeset/3`; the callbacks receive the filter as `{name, config}` ([custom filter guide](https://hexdocs.pm/backpex/custom-filter.html)). A filter module that defines `query/4`, `type/1` or `validate/2` doesn't compile.
- `item_actions(default_actions)` receives `show:`, `edit:` and `delete:` and returns the keyword list to use, e.g. `Keyword.delete(default_actions, :delete) ++ [archive: %{module: MyAppWeb.ItemActions.Archive, only: [:row, :show]}]`. An item action module does `use BackpexWeb, :item_action` and implements `icon/2`, `label/2` and either `handle/3` or `link/2`; `fields/0` and `changeset/3` add a form.
- `resource_actions/0` returns `invite: %{module: MyAppWeb.ResourceActions.Invite}`; the module does `use Backpex.ResourceAction` and implements `title/0`, `label/0`, `fields/0`, `changeset/3` and `handle/2`.
- `metrics/0` returns `total: %{module: Backpex.Metrics.Value, label: "Total", select: dynamic([p], sum(p.amount)), format: &to_string/1}`. `Backpex.Metrics.Value` needs all four keys (`format: nil` shows the value as it is); the value follows the search and filters of the index view ([metrics guide](https://hexdocs.pm/backpex/metrics.html)).

## Authorization

- `can?/3` defaults to `true`, so a LiveResource allows every action until it overrides the callback: `def can?(assigns, action, item)` with `action` in `:index`, `:new`, `:show`, `:edit`, `:delete` or the key of an item or resource action. Return a boolean; any other value raises.
- Backpex checks it before every write and raises `Backpex.ForbiddenError` for an unauthorized item; `:index` and `:show` are checked in the views. Fields restrict themselves with the `can?` option, filters with the `can?` option or the `can?/1` callback of their module. Authenticate in the router pipeline.

## Translations

Backpex passes every text as `{msg, opts}` to the functions in `config :backpex, translator_function: {MyAppWeb.CoreComponents, :translate_backpex}, error_translator_function: {MyAppWeb.CoreComponents, :translate_error}`; the msgids are in `deps/backpex/priv/gettext/backpex.pot`. A LiveResource changes single texts with `translate/1`. See the [translations guide](https://hexdocs.pm/backpex/translations.html).

## Tests and upgrades

- `Backpex.Testing` finds the paths and elements of a LiveResource for `Phoenix.LiveViewTest`: `path/5`, `select_item/2`, `click_item_action/3`, `confirm_item_action/1`, `submit_form/2`.
- Backpex is 0.x and minor versions break APIs: read every upgrade guide between the old and the new version (`https://hexdocs.pm/backpex/v0-<minor>.html`) before bumping the dependency.
- Claude Code users get skills for LiveResources, fields, filters, actions and upgrades from the Backpex plugin: `/plugin marketplace add naymspace/backpex`, then `/plugin install backpex@naymspace-backpex`.
