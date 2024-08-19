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