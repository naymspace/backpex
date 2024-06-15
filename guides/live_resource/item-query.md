# Item Query

It is possible to manipulate the query when fetching resources for `index`, `show` and `edit` view.

In all queries we define a `from` query with a named binding to fetch all existing resources on `index` view or a specific resource on `show` / `edit` view.
After that, we call the `item_query` function. By default it returns the incoming query.

The `item_query` function makes it easy to add custom query expressions.

## Configuration

To add a custom query to a resource, you need to implement the [item_query/3](Backpex.LiveResource.html#c:item_query/3) callback in your resource configuration file:

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def item_query(query, :index, _assigns) do
query
|> where([post], post.published)
end
```

The example above will filter all posts by a published boolean on `index` view. We also made use of the named binding. It's always the name of the provided schema in `snake_case`. It is recommended to build your `item_query` on top of the incoming query. Otherwise you will likely get binding errors.