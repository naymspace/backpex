# Pagination

Backpex automatically paginates the index page for your resources. You can configure the pagination behavior using the `per_page_default` and `per_page_options` options in your LiveResource configuration.

## Configuration

### Default Page Size

The `per_page_default` option sets the default number of items displayed per page:

```elixir
use Backpex.LiveResource,
  # ...other options
  per_page_default: 25
```

If not specified, the default is `15`.

### Page Size Options

The `per_page_options` option defines the available page size choices shown to users:

```elixir
use Backpex.LiveResource,
  # ...other options
  per_page_options: [10, 25, 50, 100]
```

If not specified, the default options are `[15, 50, 100]`.

### Complete Example

```elixir
defmodule MyAppWeb.PostLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: MyApp.Post,
      repo: MyApp.Repo,
      update_changeset: &MyApp.Post.changeset/3,
      create_changeset: &MyApp.Post.changeset/3
    ],
    layout: {MyAppWeb.Layouts, :admin},
    per_page_default: 25,
    per_page_options: [10, 25, 50, 100]

  # ... rest of your LiveResource
end
```

## URL Parameters

Users can change pagination through URL parameters:

- `page` - The current page number (starting from 1)
- `per_page` - Items per page (must be one of your `per_page_options`)

For example: `/admin/posts?page=2&per_page=50`

### Validation

Backpex validates pagination parameters from the URL:

| Parameter | Validation | Invalid Value Behavior |
|-----------|------------|----------------------|
| `page` | Must be a positive integer | Falls back to `1` |
| `per_page` | Must be in `per_page_options` | Falls back to `per_page_default` |

Invalid URL parameters won't crash the application. Instead, they are silently replaced with sensible defaults. This ensures your application remains stable even when users manually edit URLs or share malformed links.

### Page Clamping

If a user requests a page number that exceeds the total number of pages (e.g., `?page=999` when there are only 5 pages), Backpex automatically redirects to the last available page.

> #### Two-Phase Page Validation {: .info}
>
> Page validation happens in two phases:
>
> 1. **Initial validation**: The `page` parameter is validated as a positive integer. Invalid values (negative numbers, non-integers) fall back to `1`.
> 2. **Page clamping**: After counting the total items, the page is clamped to the valid range `[1, total_pages]`. This ensures users can't request pages beyond the available data.
>
> This two-phase approach is necessary because the total number of pages depends on the item count, which requires a database query with the current filters applied.
