# Backpex

[![CI](https://github.com/naymspace/backpex/actions/workflows/ci.yml/badge.svg)](https://github.com/naymspace/backpex/actions/workflows/ci.yml)
[![Hex](https://img.shields.io/hexpm/v/backpex.svg)](https://hex.pm/packages/backpex)
[![Hex Docs](https://img.shields.io/badge/hex-docs-green)](https://hexdocs.pm/backpex)

Backpex is a simple admin dashboard that makes it easy to manage existing resources in your application.

See our comprehensive [docs](https://hexdocs.pm/backpex) for more information.

## Development

### Requirements

- [Docker](https://www.docker.com/)
- [Mutagen Compose](https://mutagen.io/documentation/orchestration/compose)

### Recommended Extensions

- [Editorconfig](http://editorconfig.org)
- [JavaScript Standard Style](https://github.com/standard/standard#are-there-text-editor-plugins)

### Setup

- Clone the repository.
- In `demo` directpry run `cp .env.example .env` and set values accordingly.
  - Generate `SECRET_KEY_BASE` via `mix phx.gen.secret`.
  - Generate `LIVE_VIEW_SIGNING_SALT` via `mix phx.gen.secret 32`.
- Run `mutagen-compose up` (`yarn watch` is triggered autoamtically).
- Run `mix dialyzer --plt` inside the `app` container to generate the initial PLT file.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## License

Backpex source code is licensed under the [MIT License](LICENSE.md).
