Backpex is the library in the repository root; `demo/` is a Phoenix app that uses it. `CONTRIBUTING.md` covers setup, ports and test commands for everyone; this file adds what agents need on top.

**Tests** of a Backpex feature go in the library: `test/` for units, `integration_test/` for anything that needs a LiveView, the database or a browser. The demo's tests only smoke-test its own LiveResources.

**Coding standards:** before writing or reviewing Elixir, HEEx, JavaScript, tests, guides or translations, read `CODING_STANDARDS.md`. It also links the upstream rules of Phoenix, Igniter, Sobelow and PhoenixTest.Playwright.

## Environment

- Backpex commands (`mix`, `bun`) run on the host in the repository root. Demo commands run in its container: `docker compose exec -T app <command>`.
- Run `docker compose` only from the current checkout; the containers of other worktrees belong to other sessions.
- `.env` is a developer's personal file; leave it unread.
- The demo's URL is `docker compose port app 4000`. For fixed ports or a working LiveDebugger, write a `compose.override.yml` as in CONTRIBUTING.md › Setting up your development environment, with free ports (`lsof -iTCP:<port> -sTCP:LISTEN` prints nothing), and print the URL.
- Package docs: Tidewave MCP (`.mcp.json`) serves them through this checkout's app container. Pass `port: 4000`, the container port, never the host port. It connects only if the container ran at session start; otherwise start the demo with `docker compose up -d` and ask the user to reconnect `tidewave` via `/mcp`. On the host, `mix usage_rules.docs <Module.fun/arity>` prints the docs of Backpex's dependencies.

## Finish

- Run `MIX_ENV=test mix lint`: it compiles, formats, runs credo and the tests, so the `postgres` service must run. After demo changes, also run `docker compose exec -T app bun run lint`.
- Check UI changes in the demo with the Chrome DevTools MCP at mobile, tablet and desktop widths, and read the console. An empty database gets data from the seed command in CONTRIBUTING.md › Setting up your development environment.
