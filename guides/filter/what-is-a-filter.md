# What is a Filter?

Filters are used to filter the data that is being displayed in the (index) view. They are used to narrow down the data that is being displayed based on certain criteria.

Backpex allows you to define filters for your *LiveResources*. Backpex handles the filtering of the data for you as well as the UI for the filters. You just need to define the filters and Backpex will take care of the rest.

Backpex ships with a set of default filters that can be used to filter the data. In addition to the default filters, you can create custom filters for more advanced use cases.

## Built-in Filters

Backpex provides the following built-in filters:

- `Backpex.Filters.Boolean`
- `Backpex.Filters.Range`
- `Backpex.Filters.Select`
- `Backpex.Filters.MultiSelect`

You can click on each filter type to see its documentation and configuration options.

We will go through how to define filters for a *LiveResource* in [the next section](how-to-add-a-filter.md).
