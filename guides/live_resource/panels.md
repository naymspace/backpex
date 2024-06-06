# Panels

You can define panels to group certain fields together. Panels are displayed in the provided order.

## Configuration

To add panels to a resource, you need to implement the [panels/0](Backpex.LiveResource.html#c:panels/0) callback in your resource configuration file. It has to return a keyword list with an identifier and label for each panel.

```elixir

# in your resource configuration file
@impl Backpex.LiveResource
def panels do
  [
    contact: "Contact"
  ]
end
```

The example above will define a panel with the identifier `contact` and the label `Contact`.

## Usage

You can move fields into panels with the `panel` field configuration that has to return the identifier of the corresponding panel. Fields without a panel are displayed in the `:default` panel. The `:default` panel has no label.

```elixir
# in your fields list
@impl Backpex.LiveResource
def fields do
  [
    %{
      ...,
      panel: :contact
    }
  ]
end
```

The example above will move the field into the `contact` panel.

> #### Info {: .info}
>
> Note that a panel is not displayed when there are no fields in it.
