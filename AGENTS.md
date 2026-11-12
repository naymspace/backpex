Backpex is the library in the repository root; `demo/` is a Phoenix app that uses it. `CONTRIBUTING.md` covers setup, ports and test commands for everyone; this file adds what agents need on top.

**Words:** *maintainers* are the Backpex team you work for. A *user* is a developer whose app uses Backpex; an *admin* is the person working in the admin panel that app generates. The *demo* is `demo/`; the *test app* is `integration_test/support/app`.

**Tests** of a Backpex feature go in the library: `test/` for units, `integration_test/` for anything that needs a LiveView, the database or a browser. The demo's tests only smoke-test its own LiveResources.

**Coding standards:** before writing or reviewing Elixir, HEEx, JavaScript, tests, guides or translations, read `CODING_STANDARDS.md`. It also links the upstream rules of Phoenix, Igniter, Sobelow and PhoenixTest.Playwright.

**Pull requests:** before opening one, read CONTRIBUTING.md › Pull Requests.

## Environment

- Backpex commands (`mix`, `bun`) run on the host in the repository root. Demo commands run in its container: `docker compose exec -T app <command>`.
- Run `docker compose` only from the current checkout: each worktree runs its own demo and postgres for a parallel session, and stopping them breaks that session's work.
- `.env` holds a developer's personal settings; leave it unread.
- The demo's URL is `docker compose port app 4000`. For fixed ports or a working LiveDebugger, write a `compose.override.yml` as in CONTRIBUTING.md › Setting up your development environment, with free ports (`lsof -iTCP:<port> -sTCP:LISTEN` prints nothing), and print the URL.
- Package docs: Tidewave MCP (`.mcp.json`) serves them through this checkout's app container, so pass `port: 4000`, the container port, never the host port. It connects only if the container ran at session start; otherwise start the demo with `docker compose up -d` and ask the user to reconnect `tidewave` via `/mcp`. On the host, `mix usage_rules.docs <Module.fun/arity>` prints the docs of Backpex's dependencies.

## Finish

- **Surfaces:** a change that works where you tested it is often missing elsewhere. Before calling it done, walk this list and say which entries applied:
  - Views: index (with `index_editable`), show, the form for `:new` and `:edit`, panels, metrics, resource actions, and item actions in each `only:` placement (`:row`, `:index`, `:show`).
  - Built-ins: every field in `lib/backpex/fields/` and filter in `lib/backpex/filters/` the change touches; the association fields (`BelongsTo`, `HasMany`, `HasManyThrough`, `InlineCRUD`) each on their own.
  - Adapter boundary: the change goes through `Backpex.Adapter`, so other adapters (e.g. ash_backpex) can follow.
  - Texts: `Backpex.__/2` and `priv/gettext/backpex.pot`.
  - Accessibility, themes and mobile width.
  - A fixture of the test app covers the new case.
  - User docs: a change to public API or behaviour updates every place users read about it: the moduledoc, the guide in `guides/`, `usage-rules.md`, the skill in `plugin/skills/` for that area, and for a breaking change the upgrade guide (CODING_STANDARDS.md › Breaking changes).
- Run `MIX_ENV=test mix lint`: it compiles, formats, runs credo and the tests, so the `postgres` service must run. `MIX_ENV=test mix ci` adds the other checks of the CI job `test` (JS lint and tests, gettext, sobelow, docs, assets); run it before opening a PR. After demo changes, also run `docker compose exec -T app bun run lint`.
- Check UI changes in the demo with the Chrome DevTools MCP at mobile, tablet and desktop widths, and read the console. An empty database gets data from the seed command in CONTRIBUTING.md › Setting up your development environment.
