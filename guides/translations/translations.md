# Translations

You are able to translate all strings used by Backpex. This includes general strings like "New", "Edit", "Delete", as well as error messages.

## Setup

### Configuration

In order to translate strings, you need to configure two translator functions in your application config:

```elixir
config :backpex,
  translator_function: {MyAppWeb.CoreComponents, :translate_backpex},
  error_translator_function: {MyAppWeb.CoreComponents, :translate_error}
```

The first one is being used to translate general strings. The second one is being used to translate (changeset) errors.

### Using Gettext

We recommend using Gettext for translations. If you want to use it, the translator functions should look like this:

```elixir
def translate_backpex({msg, opts}) do
  if count = opts[:count] do
    Gettext.dngettext(MyAppWeb.Gettext, "backpex", msg, msg, count, opts)
  else
    Gettext.dgettext(MyAppWeb.Gettext, "backpex", msg, opts)
  end
end

def translate_error({msg, opts}) do
  if count = opts[:count] do
    Gettext.dngettext(DemoWeb.Gettext, "errors", msg, msg, count, opts)
  else
    Gettext.dgettext(DemoWeb.Gettext, "errors", msg, opts)
  end
end
```

You can place the functions in a module of your choice. In this example, we use `MyAppWeb.CoreComponents`. Don't forget to use the correct module in your config as well.

You will also need to create a Gettext template file in your application. You can use the [this](https://github.com/naymspace/backpex/blob/main/priv/gettext/backpex.pot) template from our GitHub repository as it contains all the translations used by Backpex. Note that this file may contain unreleased translations, so be sure to select the tag that matches your version in the branch selection input in the top left corner.

> #### Warning {: .warning}
>
> If you copy the above mentioned `backpex.pot` file, you should remove the `elixir-autogen` comments. Otherwise, running the `gettext.extract --merge` task will remove the translations from your project.
## Modify texts (per `LiveResource`)

In addition to translating texts, Backpex provides a way to modify texts per LiveResource with the `c:Backpex.LiveResource.translate/1` callback.

You can use it to match on any text and either translate or modify it.

See the [the backpex.pot file](https://github.com/naymspace/backpex/blob/main/priv/gettext/backpex.pot) in our GitHub repository for all available translations to match on.

The `opts` param (map) contains all the bindings you might need to construct a text. You can find the bindings inside the texts, e.g. the text "New %{resource}" will get at least one binding named `resource` (e.g. `%{resource: "User"}`).

```elixir
# in your LiveResource
@impl Backpex.LiveResource
def translate({"Cancel", _opts}), do: gettext("Go back")
def translate({"Save", _opts}), do: gettext("Continue")
def translate({"New %{resource}", opts}), do: gettext("Create %{resource}", opts)
```

> #### Info {: .info}
>
> Note that you cannot change form errors with the `translate/1` callback as you can already define a custom `translate_error` function
> per field. See [error customization guide](guides/fields/error-customization.md) for detailed information.
