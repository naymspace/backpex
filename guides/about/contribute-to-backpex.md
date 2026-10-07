# Contribute to Backpex

We are excited to have you contribute to Backpex! We are always looking for ways to improve the project and welcome any contributions in the form of bug reports, feature requests, documentation improvements, code contributions, and more.

## What can I contribute?

We provide a roadmap and a list of issues that you can work on to contribute to Backpex.

- Roadmap: https://github.com/orgs/naymspace/projects/2
- Issues: https://github.com/naymspace/backpex/issues

Especially, [issues labeled with `good-first-issue`](https://github.com/naymspace/backpex/labels/good-first-issue) are a good starting point for new contributors.

We also use GitHub's discussion feature to discuss new ideas and features.

- Discussions: https://github.com/naymspace/backpex/discussions

If you don't find an issue that you want to work on, you can always contribute to Backpex by:

- Reporting bugs (create an issue)
- Requesting new features (use the discussions)
- Improving the documentation
- Improving the demo application

## Fork the repository

In order to contribute to Backpex, you need to fork the repository. You can do this by clicking the "Fork" button in the top right corner of the repository page at [https://github.com/naymspace/backpex](https://github.com/naymspace/backpex).

## Clone the repository

After forking the repository, you need to clone it to your local machine. You can do this by running the `git clone` command along with the URL of your forked repository.

## Setting up your development environment

You can start the development environment by running the following command in the root directory of the project:

```bash
docker compose up
```

Backpex comes with a demo application that you can use to test the features of the project. The command will start a PostgreSQL database and the demo application. `compose.yml` holds all settings for development, test settings live in the `config_env() == :test` block at the end of `demo/config/runtime.exs`.

Host ports are random unless you set them, so several checkouts (e.g. git worktrees) can run side by side. `docker compose port app 4000` shows the port Docker picked. To always use [http://localhost:4000](http://localhost:4000), create a `.env` file in the root directory of the project:

```bash
APP_HOST_PORT=4000
LIVE_DEBUGGER_HOST_PORT=4007
POSTGRES_HOST_PORT=54321
```

The `.env` file is optional and also the place for personal settings such as `PLUG_EDITOR`.

Without fixed ports, absolute URLs and LiveDebugger still point to ports 4000 and 4007, so the browser console shows errors for the LiveDebugger assets. A further checkout that needs them can add a `compose.override.yml` (ignored by git) with free ports:

```yaml
services:
  app:
    ports:
      - 4100:4000
      - 4107:4007
    environment:
      URL_PORT: 4100
      LIVE_DEBUGGER_URL: http://localhost:4107
```

To insert some demo data into the database, you can run the following command:

```bash
docker compose exec app mix ecto.seed
```

## Making changes

After setting up your development environment, you can start making changes to the project. We recommend creating a new branch for your changes. After submitting your changes to your forked repository, you can create a pull request to the `develop` branch of the main repository.
