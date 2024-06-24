# Translations

You are able to translate all strings used by Backpex. This includes general strings like "New", "Edit", "Delete", etc., as well as error messages.

## Configuration

In order to translate strings, you need to configure two translator functions in your application config:

```elixir
config :backpex,
  translator_function: {MyAppWeb.CoreComponents, :translate_backpex},
  error_translator_function: {MyAppWeb.CoreComponents, :translate_error}
```

The first one is being used to translate general strings. The second one is being used to translate (changeset) errors.

## Using Gettext

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

```po
## This file is a PO Template file.
msgid ""
msgstr ""

msgid "New %{resource}"
msgstr ""

msgid "Edit %{resource}"
msgstr ""

msgid "Delete"
msgstr ""

msgid "Edit"
msgstr ""

msgid "Save"
msgstr ""

msgid "Cancel"
msgstr ""

msgid "Search"
msgstr ""

msgid "Filters"
msgstr ""

msgid "Are you sure you want to delete %{count} items?"
msgstr ""

msgid "Are you sure you want to delete the item?"
msgstr ""

msgid "New %{resource} has been created successfully."
msgstr ""

msgid "%{resource} has been edited successfully."
msgstr ""

msgid "%{resource} has been deleted successfully."
msgstr ""

msgid "%{count} %{resources} have been deleted successfully."
msgstr ""

msgid "An error occurred while deleting the %{resource}!"
msgstr ""

msgid "An error occurred while deleting %{count} %{resources}!"
msgstr ""

msgid "The item is used elsewhere."
msgstr ""

msgid "The items are used elsewhere."
msgstr ""

msgid "You are not allowed to do this!"
msgstr ""

msgid "Upload a file"
msgstr ""

msgid "or drag and drop"
msgstr ""

msgid "too large"
msgstr ""

msgid "too many files"
msgstr ""

msgid "unacceptable file type"
msgstr ""

msgid "clear"
msgstr ""

msgid "No %{resources} found"
msgstr ""

msgid "Try a different search term."
msgstr ""

msgid "Try a different filter setting or clear all filters."
msgstr ""

msgid "Get started by creating new %{resources}."
msgstr ""

msgid "Select options..."
msgstr ""

msgid "No options found"
msgstr ""

msgid "Select all"
msgstr ""

msgid "Deselect all"
msgstr ""

msgid "Show more"
msgstr ""

msgid "Items %{from} to %{to}"
msgstr ""

msgid "total"
msgstr ""

msgid "There are errors in the form."
msgstr ""

msgid "Add entry"
msgstr ""

msgid "Apply"
msgstr ""

msgid "Attach %{resource}"
msgstr ""

msgid "Choose %{resource} ..."
msgstr ""

msgid "Toggle metrics"
msgstr ""

msgid "Toggle columns"
msgstr ""

msgid "Select all items"
msgstr ""

msgid "Close alert"
msgstr ""

msgid "Select item with id: %{id}"
msgstr ""

msgid "Clear %{name} filter"
msgstr ""

msgid "Edit relation with index %{index}"
msgstr ""

msgid "Detach relation with index %{index}"
msgstr ""

msgid "Error in relation with index %{index}"
msgstr ""

msgid "Close modal"
msgstr ""

msgid "Unselect %{label}"
msgstr ""

msgid "selected"
msgstr ""

msgid "From"
msgstr ""

msgid "To"
msgstr ""
```
