# Claude Code Plugin

Backpex ships with a [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that gives AI assistants deep knowledge of Backpex conventions, APIs, and patterns. This means Claude can generate correct Backpex code (filters, fields, actions, and LiveResources) without you having to explain the framework from scratch.

## Install the Backpex Plugin

The plugin is distributed as a Claude Code marketplace directly from the Backpex repository.

### Add the Marketplace

Open Claude Code and run:

```bash
/plugin marketplace add naymspace/backpex
```

This registers the Backpex marketplace so you can browse and install plugins from it.

### Install the Plugin

```bash
/plugin install backpex@naymspace-backpex
```

After installation, run `/reload-plugins` to activate the plugin.

## What the Plugin Provides

The Backpex plugin includes skills, specialized knowledge modules that Claude uses automatically when working on Backpex projects.

### Create Live Resource

The `create-live-resource` skill helps scaffold complete LiveResource modules. It covers `adapter_config`, required callbacks (`singular_name/0`, `plural_name/0`, `fields/0`, `layout/1`), optional callbacks like `can?/3` and `filters/0`, and router setup with `live_resources/3`.

Example: "Create a LiveResource for my Product schema with name, price, and category fields"

### Create Field

The `create-field` skill covers all 17 built-in field types and how to create custom fields implementing `Backpex.Field`. It includes the config schema, required callbacks (`render_value/1`, `render_form/1`), common field options, and template assigns.

Example: "Add a color picker field to my ProductLive resource"

### Create Filter

The `create-filter` skill covers all built-in filter types (Boolean, Select, MultiSelect, Range) and custom filters. It includes required callbacks, how to wire filters into `filters/0`, and options like presets and defaults.

Example: "Add a published filter to PostLive"

### Create Item Action

The `create-item-action` skill helps create custom actions for table rows and the show page. It covers the `handle/3` vs `link/2` pattern, form fields with confirmation dialogs, and how to modify the default actions (show, edit, delete).

Example: "Add an archive action that soft-deletes selected posts"

### Create Resource Action

The `create-resource-action` skill helps create resource-level actions like exports, imports, or invitations. It covers the required callbacks (`title/0`, `label/0`, `fields/0`, `changeset/3`, `handle/2`) and schemaless changeset patterns.

Example: "Create an export action that lets users download posts as CSV"

### Upgrade

The `upgrade` skill assists with Backpex version upgrades. It reads the relevant upgrade guides, identifies breaking changes, and applies migrations systematically.

Example: "Upgrade Backpex from 0.16 to 0.18"

## Invoking Skills

All skills are triggered automatically by Claude when it detects relevant work. You can also invoke them directly:

```bash
/backpex:create-live-resource
/backpex:create-field
/backpex:create-filter
/backpex:create-item-action
/backpex:create-resource-action
/backpex:upgrade
```
