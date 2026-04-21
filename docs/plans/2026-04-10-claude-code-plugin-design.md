# Backpex Claude Code Plugin — Design

## Summary

Ship a Claude Code plugin marketplace directly in the `naymspace/backpex` repo. The first plugin (`backpex`) contains a `create-filter` skill that gives Claude deep knowledge of Backpex filter types so it can generate correct filter modules and wire them into LiveResources.

## Decisions

- **Marketplace location**: In the Backpex repo itself (`.claude-plugin/marketplace.json`)
- **Plugin name**: `backpex` — skills namespaced as `/backpex:create-filter`
- **Skill approach**: Context-aware assistant with comprehensive reference material (not a rigid generator)
- **Invocation**: Model-invocable (Claude auto-triggers when filter work is detected) + user-invocable via `/backpex:create-filter`

## Directory Structure

```
backpex/
├── .claude-plugin/
│   ├── marketplace.json      # marketplace catalog
│   └── plugin.json           # plugin manifest
├── skills/
│   └── create-filter/
│       └── SKILL.md          # filter creation skill
├── lib/                      # existing library code
├── demo/                     # existing demo app
└── ...
```

## Marketplace Config

`marketplace.json` lists one plugin sourced from the repo root (`"./"`). Named `naymspace-backpex` so users add it with `/plugin marketplace add naymspace/backpex`.

## Plugin Manifest

Minimal `plugin.json` with name, description, version, and author. Uses default directory locations (`skills/`).

## Skill: create-filter

SKILL.md provides:
- Instructions for Claude to analyze the user's request and pick the right filter type
- Complete reference for all 4 built-in filter types (Boolean, Select, MultiSelect, Range)
- Required callbacks and signatures for each type
- Conventions: module naming, file location, LiveResource `filters/0` declaration
- Custom filter guidance for when built-ins don't fit

## Future Skills

Additional skills can be added as directories under `skills/`:
- `create-field` — generate custom field type modules
- `create-resource-action` — generate resource action modules
- `create-live-resource` — scaffold a full LiveResource
