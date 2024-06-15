# Computed Fields

In some cases you want to compute new fields based on existing fields. Backpex adds a way to support this.

## Configuration

There is a `select` option you may add to a field. This option has to return a `dynamic`. This query will then be executed to select fields when listing your resources. In addition this query will also be used to order / search this field.

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def fields do
[
    total: %{
        module: Backpex.Fields.Integer,
        label: "Total",
        select: dynamic([post: p], fragment("likes + dislikes")),
    }
]
end
```

The example above will compute the value of the total field based on the `likes` and `dislikes` fields.

## Example

Imagine there is a user table with `first_name` and `last_name`. Now, on your index view you want to add a column to display the `full_name`. You could create a generated column in you database, but there are several reasons for not adding generated columns for all computed fields you want to display in your application.

You can display the `full_name` of your users by adding the following field to the resource configuration file.

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def fields do
[
    full_name: %{
        module: Backpex.Fields.Text,
        label: "Full Name",
        searchable: true,
        except: [:edit],
        select: dynamic([user: u], fragment("concat(?, ' ', ?)", u.first_name, u.last_name))
    }
]
end
```

We are using a database fragment to build the `full_name` based on the `first_name` and `last_name` of an user. Backpex will select this field when listing resources automatically. Ordering and searching works the same like on all other fields, because Backpex uses the query you provided in the `dynamic` in order / search queries, too.

We recommend to display this field on `index` and `show` view only.

> #### Important {: .info}
>
> Note: You are required to add a virtual field `full_name` to your user schema. Otherwise, Backpex is not able to select this field.

## Computed Fields with Associations

Computed fields also work with associations.

For example, you are able to add a `select` query to a `Backpex.Field.BelongsTo` field.

Imagine you want to display a list of posts with the corresponding authors (users). The user column should be a `full_name` computed by the `first_name` and `last_name`:

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def fields do
[
    user: %{
        module: Backpex.Fields.BelongsTo,
        label: "Full Name",
        display_field: :full_name,
        select: dynamic([user: u], fragment("concat(?, ' ', ?)", u.first_name, u.last_name)),
        options_query: fn query, _assigns ->
            query |> select_merge([user], %{full_name: fragment("concat(?, ' ', ?)", user.first_name, user.last_name)})
        end
    }
]
end
```

We recommend to add a `select_merge` to the `options_query` where you select the same field. Otherwise, displaying the same values in the select form on edit page will not work.

Do not forget to add the virtual field `full_name` to your user schema in this example, too.
