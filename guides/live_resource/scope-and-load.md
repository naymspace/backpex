# Scope and Load

A LiveResource limits and enriches the items it reads with three callbacks. They return expressions (see
`Backpex.Expr`) and lists, not queries, so they work with every adapter.

## Scope

`c:Backpex.LiveResource.scope/1` returns an expression that every item of the resource matches, e.g. to hide soft
deleted users or to show the records of the current tenant only. Backpex adds it to every read: the index view, its
count and metrics, the show and edit views and the items item actions are applied to.

```elixir
# in your resource configuration file
import Backpex.Expr

@impl Backpex.LiveResource
def scope(%{current_user: user}) do
  if user.role == :admin do
    expr(team_id == ^user.team_id)
  else
    expr(team_id == ^user.team_id and user_id == ^user.id)
  end
end
```

Return `nil` to keep all items.

## Load

`c:Backpex.LiveResource.load/1` returns the relationships to load into the items, besides the ones of the association
fields, e.g. for the `render` function of a field that shows related data. Nest them like the preloads of Ecto:

```elixir
@impl Backpex.LiveResource
def load(_assigns), do: [:category, author: :team, comments: [:author]]
```

`Backpex.Query.related/1` sorts, filters, loads and computes values of the related items:

```elixir
@impl Backpex.LiveResource
def load(_assigns) do
  [
    comments: Backpex.Query.related(sort: [inserted_at: :desc]),
    user: Backpex.Query.related(load: [:team], computed: [team_name: expr(team.name)])
  ]
end
```

## Computed values

`c:Backpex.LiveResource.computed/1` returns values Backpex computes for every item, see the
[computed fields](computed-fields.md) guide.

## Order

The `:init_order` option takes a path through relationships to one item or the name of a computed value, e.g.
`%{by: :"author.last_name", direction: :asc}`.
