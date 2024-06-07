# Alignment

It is possible to align the fields of a resource in the index view and the labels of the fields in the edit view.

## Field Alignment (Index View)

You can align the fields of a resource in the index view by setting the `align` option in the field configuration.

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

The example above will align the field to the center in the index view.

## Label Alignment (Edit View)

You can align the labels of the fields in the edit view by setting the `label_align` option in the field configuration.

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

The example above will align the label to the top in the edit view.