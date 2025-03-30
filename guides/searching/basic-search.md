# Search

Backpex provides a simple search feature that allows you to search for records in your resources. You can search for records based on the values of the fields in your resources.

> #### Info {: .info}
>
> Note that fields are searched using a case-insensitive `ilike` query.

## Configuration

To enable searching, you need to flag the fields you want to search on as `searchable`.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    %{
        ...,
        searchable: true
    }
]
end
```

A search input will appear automatically on the resource index view.

In addition to basic searching, Backpex allows you to perform full-text searches on resources (see [Full-Text Search Guide](full-text-search.md)).