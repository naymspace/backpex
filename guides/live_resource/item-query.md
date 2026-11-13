# Item Query

It is possible to manipulate the query when fetching resources for `index`, `show` and `edit` view when using
`Backpex.Adapters.Ecto`.

> #### Scope {: .tip}
>
> To limit the items of a resource, e.g. to the posts of the current user, prefer the `c:Backpex.LiveResource.scope/1`
> callback. It returns an expression (see `Backpex.Expr`) and works with every adapter:
>
> ```elixir
> import Backpex.Expr
>
> @impl Backpex.LiveResource
> def scope(assigns), do: expr(user_id == ^assigns.current_user.id)
> ```
>
> Use `item_query` for what only an Ecto query can do, e.g. joins.

In all queries we define a `from` query with a named binding to fetch all existing resources on `index` view or a specific resource on `show` / `edit` view.
After that, we call the `item_query` function. By default it returns the incoming query.

The `item_query` function makes it easy to add custom query expressions.

## Configuration

To add a custom query to a resource, you need to provide a function to the `item_query` option in your `adapter_config`.

```elixir
# in your resource configuration file (live resource)
use Backpex.LiveResource,
  # ...other options
  adapter_config: [
    # ...other adapter options
    item_query: &__MODULE__.item_query/3
  ]

  def item_query(query, :index, _assigns) do
    query
    |> where([post], post.published)
  end

  def item_query(query, _live_action, _assigns) do
    query
  end
```

The example above will filter all posts by a published boolean on `index` view. We also made use of the named binding. It's always the name of the provided schema in `snake_case`. It is recommended to build your `item_query` on top of the incoming query. Otherwise you will likely get binding errors.

Make sure to always cover all possible cases or add a fallback `item_query/3` function that just returns the query.

> #### Important {: .info}
>
> Note that it is not possible to use an anonymous function for `item_query` configuration. You must refer to a public function defined within a module.
