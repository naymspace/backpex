# Visibility

You can change the visibility of fields in certain views.

## Visibility with `only` and `except`

You can use the `only` and `except` options to define the views where a field should be visible. The `only` option will show the field only in the specified views, while the `except` option will show the field in all views except the specified ones. The options have to be a list of view names.

The following values are supported: `:new`, `:edit`, `:show` and `:index`.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    likes: %{
        module: Backpex.Fields.Number,
        label: "Likes",
        only: [:show, :edit]
    }
]
end
```

The example above will show the `likes` field only in the show and edit views.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    likes: %{
        module: Backpex.Fields.Number,
        label: "Likes",
        except: [:new]
    }
]
end
```

The example above will show the `likes` field in all views except the new view.

## Visibility with `visible`

> #### Important {: .info}
>
> Note that the option `visible` is only available for the show and edit views.

To change the visibility of a field, you can also set the `visible` option in the field configuration. The `visible` option has to return a function that receives the assigns and returns a boolean value.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    likes: %{
        module: Backpex.Fields.Number,
        label: "Likes",
        visible: fn assigns ->
            assigns.current_user.role in [:admin]
        end
    }
]
end
```

The example above will show the `likes` field only to users with the `admin` role.


> #### Warning {: .warning}
>
> Note that hidden fields are not exempt from validation by Backpex itself and the visible function is not executed on `:index`.

## Visibility with `can?`

In addition to the `visible` option, we provide a `can?` option that you can use to determine the visibility of a field.

It can also be used on `:index`. It takes the `assigns` as a parameter and has to return a boolean value.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created At",
        can?: fn
            %{live_action: :show} = _assigns ->
            true

            _assigns ->
            false
        end
    }
]
end
```

Also see the [field authorization](/guides/authorization/field-authorization.md) guide.

## Advanced Example

Imagine you want to implement a checkbox in order to toggle an input field (post likes). The input field should be visible when it has a certain value (post likes > 0).

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    # show_likes is a virtual field in the post schema
    show_likes: %{
        module: Backpex.Fields.Boolean,
        label: "Show likes",
        # initialize the button based on the likes value
        select: dynamic([post: p], fragment("? > 0", p.likes)),
    },
    likes: %{
        module: Backpex.Fields.Number,
        label: "Likes",
        # display the field based on the `show_likes` value
        # the value can be part of the changeset or item (when edit view is opened initially).
        visible: fn
            %{live_action: :new} = assigns ->
            Map.get(assigns.changeset.changes, :show_likes)

            %{live_action: :edit} = assigns ->
            Map.get(assigns.changeset.changes, :show_likes, Map.get(assigns.item, :show_likes, false))

            _assigns ->
            true
        end
    }
]
end
```
