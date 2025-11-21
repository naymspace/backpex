# Alignment

It is possible to align the field values of a resource on index views and the labels of the fields on edit views.

## Field Alignment (Index Views)

You can align the field values of a resource on index views by setting the `align` option in the field configuration.

The following alignments are supported: `:left`, `:center` and `:right`

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def fields do
[
  %{
    ...,
    align: :center
  }
]
end
```

The example above will center the field value on the index view.

## Label Alignment (Form Views)

You can align the labels of the fields on form views by setting the `label_align` option in the field configuration.

The following label orientations are supported: `:top`, `:center` and `:bottom`.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
  %{
    ...,
    align_label: :top
  }
]
end
```

The example above will align the label to the top on the form view.
