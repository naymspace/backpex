# Context

## Project Overview

Backpex is a highly customizable administration panel for Phoenix LiveView applications. It allows you to quickly create CRUD views of your existing data using configurable LiveResources. Backpex integrates seamlessly with your existing Phoenix LiveView application and provides an easy way to manage your resources. It is highly customizable and can be extended with your own layouts, views, field types, filters and more.

**Key Features**:
- **LiveResources**: Quickly create LiveResource modules for your database tables with fully customizable CRUD views. Bring your own layout or use our components.
- **Search and Filters**: Define searchable fields and add custom filters for instant, LiveView-powered results.
- **Resource Actions**: Implement global custom actions like user invitations or exports, with support for additional form fields.
- **Authorization**: Handle CRUD and custom action authorization via simple pattern matching, with optional integration for external authorization libraries.
- **Field Types**: Out-of-the-box support for Text, Number, Date, Upload, and more. Easily extend with your own custom field type modules.
- **Associations**: Effortlessly handle HasOne, BelongsTo, and HasMany(Through) associations with minimal configuration. Customize available options and rendered columns.
- **Metrics**: Add value metrics such as sums or averages for quick data insights, with more metric types on the horizon.

## Tech Stack

### Programming Language

- **Elixir**: Functional programming language for building scalable and maintainable applications

### Framework

- **Phoenix LiveView**: Real-time web framework for Elixir

### Styling

- **Tailwind CSS**: utility-first CSS framework
- **daisyUI**: Tailwind CSS plugin and component library

## Architecture

Backpex follows a modular architecture that separates the library code from the demonstration application. The project is structured as an Elixir library that can be integrated into Phoenix LiveView applications.

### Project Structure

The repository contains two main parts:

**1. Backpex Library (`/`)**

The root directory contains the Backpex library itself, which is published as a Hex package. Key directories:

```
lib/backpex/
├── adapters/          # Data layer adapters (Ecto)
├── controllers/       # Phoenix controllers (cookie management)
├── fields/            # Built-in field types (Text, Number, Date, BelongsTo, HasMany, etc.)
├── filters/           # Built-in filter types (Boolean, Select, Range, etc.)
├── html/              # Phoenix Components for UI rendering
│   ├── core_components.ex    # Base UI components
│   ├── layout.ex              # Layout components
│   ├── form.ex                # Form components
│   └── resource.ex            # Resource-specific components
├── item_actions/      # Built-in item actions (Edit, Delete, Show)
├── live_components/   # LiveView components
├── live_resource/     # Core LiveResource views (Index, Form, Show)
├── metrics/           # Metric types (Value metrics)
├── plugs/             # Phoenix plugs (ThemeSelector)
├── adapter.ex         # Adapter behavior
├── field.ex           # Field behavior and config schema
├── live_resource.ex   # LiveResource macro and core logic
├── resource.ex        # Resource data manipulation
└── router.ex          # Routing helpers and macros

priv/
├── gettext/           # Translation files
├── static/            # Static assets (compiled JS, images)
└── templates/         # Default layout templates

assets/js/             # JavaScript for LiveView hooks
```

The library provides:
- **Core abstractions**: `LiveResource`, `Field`, `Filter`, `ItemAction`, `ResourceAction`, `Metric`
- **Adapter system**: Pluggable data layer support (Ecto by default, Ash via community project [ash_backpex](https://github.com/enoonan/ash_backpex))
- **UI components**: Reusable Phoenix Components for rendering admin interfaces
- **Routing helpers**: Macros for defining RESTful LiveView routes

**2. Demo Application (`/demo`)**

The demo directory contains a full Phoenix application that demonstrates Backpex capabilities:

```
demo/
├── lib/
│   ├── demo/              # Application logic (schemas, contexts)
│   │   └── helpdesk/      # Example domain (Tickets)
│   └── demo_web/          # Web layer
│       ├── components/    # App-specific components
│       ├── live/          # LiveResource implementations
│       │   ├── user_live.ex
│       │   ├── post_live.ex
│       │   ├── product_live.ex
│       │   └── ...
│       ├── filters/       # Custom filter implementations
│       ├── item_actions/  # Custom item actions
│       ├── resource_actions/  # Custom resource actions
│       └── router.ex      # Route definitions
├── priv/
│   ├── repo/              # Database migrations and seeds
│   └── static/            # Static assets
├── test/                  # Tests (including browser tests with Phoenix.Test.Playwright)
└── assets/                # Frontend assets (JS, CSS)
```

The demo serves multiple purposes:
- **Example implementation**: Shows how to use Backpex in a real application
- **Development environment**: Used for testing new features during development
- **Documentation**: Live examples for documentation and screenshots
- **Testing**: Comprehensive test suite including accessibility tests

### Difference Between Demo and Backpex

| Aspect | Backpex (Library) | Demo (Application) |
|--------|-------------------|-------------------|
| **Purpose** | Reusable library package | Example implementation & testing |
| **Location** | Root `/lib/backpex`, `/priv`, `/assets` | `/demo` directory |
| **Deployment** | Published to Hex.pm | Runs locally (Docker) |
| **Dependencies** | Minimal (Phoenix, Ecto, Gettext) | Includes Backpex + app-specific deps |
| **Code** | Generic, configurable abstractions | Specific LiveResource implementations |
| **Assets** | Compiled JS (hooks) published with package | Full asset pipeline with Tailwind/esbuild |
| **Tests** | Unit tests for library code | Browser tests, integration tests, a11y tests |

### Backpex is designed to be extended

1. **Custom Fields**: Implement `Backpex.Field` behavior (see `demo/lib/demo_web/fields/`)
2. **Custom Filters**: Implement `Backpex.Filter` behavior (see `demo/lib/demo_web/filters/`)
3. **Custom Actions**: Implement `Backpex.ItemAction` or `Backpex.ResourceAction` behaviors
4. **Custom Layouts**: Provide your own layout components
5. **LiveView Hooks**: Add client-side JavaScript behavior (see `assets/js/`)
6. **Adapters**: Implement `Backpex.Adapter` for new data layers

## LiveResource

A *LiveResource* in Backpex is a module that contains the configuration for a resource. This module is responsible for defining the resource's schema, the actions that can be performed on it, and the fields that will be rendered. See `demo/lib/demo_web/live/post_live.ex` for an example LiveResource.

Example structure:
```elixir
defmodule MyApp.UserLive do
  use Backpex.LiveResource,
    adapter_config: [...],
    layout: {MyAppWeb.Layouts, :admin}
  
  # Callbacks define the resource
  def fields, do: [...]
  def filters, do: [...]
  def can?(assigns, action, item), do: true
end
```

This generates:
- `MyApp.UserLive.Index` - List view with search, filters, sorting
- `MyApp.UserLive.Form` - Create/edit form (handles both :new and :edit actions)
- `MyApp.UserLive.Show` - Detail view

## Development Guidelines

### Usage Rules

Always consult the `usage_rules.md` file for the usage of packages in this project. It contains guidelines directly from package authors and additional development guidelines (e.g., for Elixir, Phoenix, and Phoenix LiveView). Review these guidelines early and often during development.

### Finding Documentation

1. **Elixir ecosystem packages**: Use Tidewave MCP to find the documentation for Elixir packages (e.g., `phoenix` and `phoenix_live_view`)
2. **Frontend libraries and other packages**: Use Context7 MCP server for daisyUI, Tailwind CSS, and other non-Elixir packages

**Before implementing features:**
- Search the codebase for similar existing patterns
- Check if there are reusable components or functions
- Understand the architectural patterns used in the project

### Running Commands

The demo project runs inside a docker container so you have to run commands inside the container as well:

```sh
docker compose exec -T app bun run lint
```

If the command is related to Backpex it has to be executed on the host system:

```sh
mix format
```

### Quality Assurance

1. **Run linters**: Use linters when you are done with all changes and fix any pending issues
  - Run `docker compose exec -T app bun run lint` to lint the demo application
  - Run `mix lint` to lint Backpex
2. **Manual testing**: Use Chrome DevTools MCP to test your changes at http://localhost:4000
  - Test in multiple browser viewports (mobile, tablet, desktop)
  - Verify all interactive elements work correctly
  - Check for console errors or warnings

### Styling

**CSS Framework Stack:**
- **Primary**: daisyUI components (built on Tailwind CSS)
- **Secondary**: Tailwind CSS utility classes
- **Approach**: Mobile-first responsive design

**Best Practices:**

1. **Component hierarchy**:
  - Look for existing Phoenix Components in the codebase (e.g., in `lib/backpex/html/*` modules)
  - Use daisyUI components when available (use Context7 to fetch documentation)
  - Build custom components with Tailwind CSS utilities and daisyUI component classes
  - Always prefer reusing existing components over creating new ones

2. **Styling daisyUI components**:
  - daisyUI components can be styled using Tailwind CSS classes
  - Add utility classes directly to daisyUI component markup: `<button class="btn btn-primary mt-4 shadow-lg">Submit</button>`

3. **Responsive design**:
  - Use mobile-first approach (base styles are for mobile, add `md:`, `lg:` prefixes for larger screens)
  - Test all breakpoints: mobile (default), tablet (`md:`), desktop (`lg:`, `xl:`)
  - Ensure touch targets are at least 44x44px on mobile

4. **Color and theming**:
  - Use daisyUI semantic color classes (`primary`, `secondary`, etc.)
  - Avoid hard-coded color values; use theme variables for consistency
  - Ensure color choices meet accessibility contrast requirements

5. **Component organization**:
  - Create reusable components in `lib/backpex/html/*` modules
  - Keep components small and focused on a single responsibility

### Translations

Users are able to translate all strings used by Backpex. If you add any translations to Backpex make sure to use the `Backpex.__/2` macro. Pass the text as the first argument. If possible, pass the LiveResource module as the second argument (often available in the socket assigns).

Example in `.ex` file:

```ex
defp apply_action(socket, :form) do
  text = Backpex.__("No options found", socket.assigns.live_resource)
end
```

Example in `.html.heex` file:

```heex
<button>
  {Backpex.__("Show more", @live_resource)}
</button>
```

### Accessibility (A11Y)

Accessibility is **mandatory**, not optional. All features must be fully accessible.

1. **Semantic HTML**: Use proper HTML5 semantic elements (`<nav>`, `<main>`, `<article>`, `<section>`, etc.)
2. **ARIA attributes**: Add ARIA labels where text content is not sufficient (`aria-label`, `aria-labelledby`)
3. **Keyboard navigation**: All interactive elements must be keyboard accessible (focusable with Tab)
4. **Visual accessibility**: Use appropriate font sizes, ensure color contrast meets accessibility requirements, and add sufficient spacing and touch target sizes
5. **Screen reader compatibility**: Provide alt text for all images, use `sr-only` Tailwind class for screen-reader-only content when needed
6. **Forms accessibility**: Always use `<label>` elements associated with form inputs

The demo project contains an `A11yAssertions` module (`demo/test/support/a11y_assertions.ex`) with an `assert_a11y/1` function that can be used to test for a11y. See `demo/test/demo_web/browser/address_browser_test.exs` for an example of this.

### Phoenix LiveView Hooks

If **absolutely necessary**, it is possible to create client hooks (LiveView hooks) via the `phx-hook` attribute to provide client-side JavaScript code. Create the hooks in the `assets/js` directory. Also export the hook in the `assets/js/index.js` file. When building hooks, analyse the existing hooks in the `assets/js` directory first and use existing patterns if possible.

See `usage_rules.md` for additional guidelines on LiveView Hooks. Fetch `phoenix` and `phoenix_live_view` docs via Tidewave MCP if needed.

### Git Workflow

1. **Commit messages**:
  - Write clear, descriptive commit messages
  - Use present tense ("Add feature" not "Added feature")
  - Reference issue numbers when applicable

2. **Branch strategy**:
  - Create feature branches for new work
  - Keep commits focused and atomic
  - Rebase or merge from main regularly to stay up to date

3. **Before pushing**:
  - Run `mix precommit` to ensure all checks pass
  - Review your own changes (diff) before committing
  - Ensure tests pass locally
