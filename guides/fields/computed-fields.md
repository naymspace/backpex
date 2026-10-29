# Computed Fields

In some cases you want to show values that are computed from other fields, e.g. the full name of a user from the first
and the last name. `c:Backpex.LiveResource.computed/1` returns these values as expressions (see `Backpex.Expr`). Backpex
computes them for every item, and a field with the same name shows the value. The index view sorts by it and searches
it like any other field.

## Configuration

```elixir
# in your resource configuration file
import Backpex.Expr

@impl Backpex.LiveResource
def computed(_assigns) do
  [
    full_name: expr(concat([first_name, last_name], " ")),
    show_likes: expr(likes > 0)
  ]
end

@impl Backpex.LiveResource
def fields do
  [
    full_name: %{
      module: Backpex.Fields.Text,
      label: "Full Name",
      searchable: true,
      except: [:edit, :new]
    }
  ]
end
```

A value can be a field of the items or of related items (e.g. `expr(author.name)`), a condition (e.g.
`expr(likes > 0)`), a string joined with `concat/2`, which leaves out `nil`, a number computed with `+`, `-`, `*` and
`/` (e.g. `expr(datetime_diff(ends_at, starts_at, :minute) - pause)`) or a value as a string with `to_string/1`. See
the [Values](`m:Backpex.Expr#module-values`) of `Backpex.Expr`. We recommend to show computed values on
the `index` and `show` views only.

> #### Important {: .info}
>
> `Backpex.Adapters.Ecto` merges the values into the selected items, so add a virtual field with the name of each
> value to your schema, e.g. `field :full_name, :string, virtual: true`.

## Aggregates of related items

`Backpex.Expr.aggregate/3` computes a value of the related items of a relationship to many items, e.g. the number of
the posts of a user, the sum of their likes or the title of the post with the most likes:

```elixir
@impl Backpex.LiveResource
def computed(_assigns) do
  [
    post_count: aggregate(:count, :posts),
    published_count: aggregate(:count, :posts, where: expr(published == true)),
    total_likes: aggregate(:sum, :posts, value: expr(likes)),
    top_post: aggregate(:first, :posts, value: expr(title), sort: [likes: :desc]),
    primary_partner: aggregate(:first, :partners_contacts, value: expr(partner.name), where: expr(primary == true))
  ]
end
```

The path can go through several relationships, e.g. `[:posts, :tags]`, and the value through relationships to one item,
e.g. `expr(partner.name)`. `Backpex.Adapters.Ecto` joins a subquery of the values by item, so an aggregate doesn't
duplicate items. The index view sorts by aggregates and searches them like any other computed value.

## Values of the database

A value the expressions can't describe, e.g. a fragment of SQL, is a native expression of the adapter (see
`Backpex.Expr.native/3`). It only works with the adapter it was written for:

```elixir
@impl Backpex.LiveResource
def computed(_assigns) do
  [
    total: Backpex.Expr.native(Backpex.Adapters.Ecto, dynamic([post: p], p.likes + p.dislikes))
  ]
end
```

## Computed Values of Associations

Values of related items are computed by the query of the relationship in `c:Backpex.LiveResource.load/1`. Imagine you
want to show a list of posts with their authors (users), and the author column shows the full name of the user:

```elixir
# in your resource configuration file
import Backpex.Expr

@impl Backpex.LiveResource
def load(_assigns) do
  [user: Backpex.Query.related(computed: [full_name: expr(concat([first_name, last_name], " "))])]
end

@impl Backpex.LiveResource
def fields do
  [
    user: %{
      module: Backpex.Fields.BelongsTo,
      label: "Author",
      display_field: :full_name,
      live_resource: MyAppWeb.UserLive
    }
  ]
end
```

The computed values of the relationship also go into the options of the field, so the select of the form shows the
full names, too. The index view sorts by the full name and searches it. Do not forget to add the virtual field
`full_name` to the user schema in this example, too.
