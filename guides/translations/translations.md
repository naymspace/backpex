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

In addition, you need to create a Gettext template file in your application. You may use the following template. It contains all translations used by Backpex.

## Modify strings

In addition to translating texts, Backpex provides a way of modifying texts per LiveResource. 

TODO

