# Filter Presets

Backpex allows you to define filter presets for your filters. Filter presets are used to define a set of filter configurations that can easily be applied to the data being displayed in the index view. Filter Presets consist of a name and a list of values that are used to filter the data. For example, you can define a filter preset for a date filter that filters the data based on the current month. Then the user can easily apply this filter by selecting the preset from the filter dropdown.

## Defining a Filter Preset

To define presets for your filters, you need to add a list of maps under the key of `:presets` to your filter in your LiveResource.

Each of those maps has two keys:
1. `:label` – the name of the preset shown to the user
2. `:values` – a function with arity 0 that returns the values corresponding to your used filter

See the example below for some preset examples. We add a preset for a date filter that filters the data based on the last 7 days and a preset for a select filter that filters the data based on the published status of an event.

```elixir
@impl Backpex.LiveResource
def filters, do: [
  begins_at: %{
    module: MyAppWeb.Filters.DateRange,
    label: "Begins At",
    presets: [
      %{
        label: "Last 7 Days",
        values: fn -> %{
          "start" => Date.add(Date.utc_today(), -7),
          "end" => Date.utc_today()
        } end
      }
    ]
  },
  published: %{
    module: MyAppWeb.Filters.EventPublished,
    presets: [
      %{
        label: "Both",
        values: fn -> [:published, :not_published] end
      },
      %{
        label: "Only published",
        values: fn -> [:published] end
      }
    ]
  }
]
```

## Preset Validation

Preset values go through the same validation as manually entered filter values. This means:

- Values are cast to the appropriate type based on the filter's `type/1` callback
- Custom validations from `changeset/3` are applied
- Invalid preset values will not be applied to the query

When defining presets, ensure the values match the expected format for your filter type:

| Filter Type | Expected Preset Value Format |
|-------------|------------------------------|
| Select | Single string value (e.g., `"active"`) |
| Boolean | List of option keys (e.g., `[:published, :draft]`) |
| MultiSelect | List of string values (e.g., `["user-1", "user-2"]`) |
| Range | Map with `"start"` and `"end"` keys |

## Related Guides

- [Filter Validation](filter-validation.md) - Comprehensive validation documentation
- [What is a Filter?](what-is-a-filter.md) - Overview of the filter system
- [How to Add a Filter](how-to-add-a-filter.md) - Adding filters to your LiveResource