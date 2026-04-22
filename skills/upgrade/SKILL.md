---
name: upgrade
description: Use when upgrading Backpex to a newer version, handling breaking changes, or migrating code after a version bump. Also use when the user asks about what changed between versions.
---

# Upgrading Backpex

You are an expert at upgrading Backpex versions. When the user wants to upgrade, follow this process:

1. **Determine current and target versions** from `mix.exs`
2. **Read the relevant upgrade guides** for each version in between
3. **Apply changes** systematically, one breaking change at a time
4. **Verify** the project compiles and tests pass after each change

## Finding the Current Version

Check `mix.exs` for the Backpex dependency:

```elixir
{:backpex, "~> 0.17.0"}
```

## Upgrade Guides Location

All upgrade guides are at `guides/upgrading/` in the Backpex repository (also available on HexDocs). Read these files directly to get the exact migration steps:

| Version | File |
|---------|------|
| 0.18 | `guides/upgrading/v0.18.md` |
| 0.17 | `guides/upgrading/v0.17.md` |
| 0.16 | `guides/upgrading/v0.16.md` |
| 0.15 | `guides/upgrading/v0.15.md` |
| 0.14 | `guides/upgrading/v0.14.md` |
| 0.13 | `guides/upgrading/v0.13.md` |
| 0.12 | `guides/upgrading/v0.12.md` |
| 0.11 | `guides/upgrading/v0.11.md` |
| 0.10 | `guides/upgrading/v0.10.md` |
| 0.9 | `guides/upgrading/v0.9.md` |
| 0.8 | `guides/upgrading/v0.8.md` |
| 0.7 | `guides/upgrading/v0.7.md` |
| 0.6 | `guides/upgrading/v0.6.md` |
| 0.5 | `guides/upgrading/v0.5.md` |
| 0.3 | `guides/upgrading/v0.3.md` |
| 0.2 | `guides/upgrading/v0.2.md` |

## Upgrade Process

1. **Read ALL upgrade guides** between current and target version. For example, upgrading from 0.15 to 0.18 requires reading v0.16, v0.17, and v0.18 guides.

2. **Bump the dependency** in `mix.exs`:
   ```elixir
   {:backpex, "~> 0.18.0"}
   ```

3. **Run `mix deps.get`** to fetch the new version.

4. **Apply breaking changes** from each guide in order. Common categories:
   - Removed or renamed options
   - New required callbacks
   - Changed callback signatures
   - Moved or renamed components
   - Removed dependencies
   - New Gettext translation strings

5. **Compile and fix warnings**: `mix compile --warnings-as-errors`

6. **Run tests** to catch regressions.

## Common Breaking Change Patterns

### Callback replaces option
```elixir
# Before (option)
use Backpex.LiveResource, layout: {MyAppWeb.Layouts, :admin}

# After (callback)
use Backpex.LiveResource, ...

@impl Backpex.LiveResource
def layout(_assigns), do: {MyAppWeb.Layouts, :admin}
```

### New required callback added
Read the upgrade guide for the default value and implement it in affected modules.

### Changed callback signature
Search your codebase for the old callback name and update all implementations.

### Removed dependency
Check if your code directly uses the removed module/function and replace with the suggested alternative.

### New Gettext strings

Each Backpex release may add new translatable strings. After upgrading:

1. Copy the updated Gettext template from the Backpex dependency into your application:
   ```bash
   cp deps/backpex/priv/gettext/backpex.pot priv/gettext/backpex.pot
   ```
   Alternatively, download it from GitHub at `https://github.com/naymspace/backpex/blob/<VERSION>/priv/gettext/backpex.pot` (replace `<VERSION>` with your target version tag).

2. **Remove `elixir-autogen` comments** from the copied `.pot` file. The Backpex source file contains `#, elixir-autogen, elixir-format` comment lines. If left in place, running `mix gettext.extract --merge` will delete all Backpex translations from your PO files (Gettext treats autogen entries as auto-generated and removes those not found in your source code). Strip them:
   ```bash
   sed -i '' 's/#, elixir-autogen, elixir-format/#, elixir-format/g' priv/gettext/backpex.pot
   ```

3. Merge the new strings into your existing PO files:
   ```bash
   mix gettext.merge priv/gettext
   ```

4. Translate any new `msgid` entries in your `priv/gettext/<locale>/LC_MESSAGES/backpex.po` files.

The `.pot` file on the `develop` branch may contain unreleased translations. Always use the version tag that matches your Backpex version.
