# What is a Filter?

Filters are used to filter the data that is being displayed in the (index) view. They are used to narrow down the data that is being displayed based on certain criteria.

Backpex allows you to define filters for your *LiveResources*. Backpex handles the filtering of the data for you as well as the UI for the filters. You just need to define the filters and Backpex will take care of the rest.

Backpex ships with a set of default filters that can be used to filter the data. In addition to the default filters, you can create custom filters for more advanced use cases.

## Key Features

- **Type Safety**: Filter values are validated and cast from URL parameters before being applied to queries
- **Validation**: Built-in and custom filters validate their values, showing inline errors for invalid input
- **Automatic UI**: Backpex renders filter forms, badges, and handles all user interactions
- **Extensible**: Create custom filters with your own validation logic and UI

## How Filters Work

1. **URL Parameters**: Filter values come from URL query parameters (e.g., `?filters[status]=active`)
2. **Type Casting**: String values are cast to appropriate types (integers, dates, etc.)
3. **Validation**: Values are validated using Ecto changesets
4. **Query Application**: Only valid filters are applied to the database query
5. **Error Display**: Invalid filters show inline errors in the UI

Invalid filters are **not applied** to the query - users see unfiltered results for that attribute while the error is displayed. This prevents crashes from malformed URL parameters while providing clear feedback.

## Built-in Filters

Backpex provides the following built-in filters:

| Filter | Use Case | Example |
|--------|----------|---------|
| `Backpex.Filters.Boolean` | Checkbox-based filtering with multiple options | Published/Draft status |
| `Backpex.Filters.Select` | Single-value dropdown selection | Category filter |
| `Backpex.Filters.MultiSelect` | Multiple-value selection | Tags, assignees |
| `Backpex.Filters.Range` | Date, datetime, or number ranges | Date range, price range |

Each built-in filter includes automatic validation:
- **Boolean**: Validates selected keys exist in your options
- **Select**: Validates the selected value exists in your options
- **MultiSelect**: Validates all selected values exist in your options
- **Range**: Validates date formats, number formats, and that start <= end

You can click on each filter type to see its documentation and configuration options.

We will go through how to define filters for a *LiveResource* in [the next section](how-to-add-a-filter.md).

## Related Guides

- [How to Add a Filter](how-to-add-a-filter.md) - Adding filters to your LiveResource
- [Custom Filters](custom-filter.md) - Creating custom filter types
- [Filter Validation](filter-validation.md) - Comprehensive validation documentation
- [Filter Presets](filter-presets.md) - Pre-configured filter combinations
