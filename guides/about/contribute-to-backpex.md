# Contribute to Backpex

We are excited to have you contribute to Backpex! We are always looking for ways to improve the project and welcome any contributions in the form of bug reports, feature requests, documentation improvements, code contributions, and more.

## What can I contribute?

We are in the process of writing a roadmap to outline the features we plan to implement in the future. In the meantime, you can contribute to Backpex by:

- Reporting bugs
- Requesting new features
- Improving the documentation
- Improving the demo application
- Fixing bugs

## Fork the repository

In order to contribute to Backpex, you need to fork the repository. You can do this by clicking the "Fork" button in the top right corner of the repository page at [https://github.com/naymspace/backpex](https://github.com/naymspace/backpex).

## Clone the repository

After forking the repository, you need to clone it to your local machine. You can do this by running the `git clone` command along with the URL of your forked repository.

## Setting up your development environment

You first need to create a `.env` file in the `demo` directory of the project with the following content:

```bash
SECRET_KEY_BASE=<SECRET_KEY_BASE>
LIVE_VIEW_SIGNING_SALT=<LIVE_VIEW_SIGNING_SALT>
```

For development purposes you can copy the values from the `demo/.env.example` file.

You can then start the development environment by running the following command in the root directory of the project:

```bash
docker compose up
```

Backpex comes with a demo application that you can use to test the features of the project. The command will start a PostgreSQL database and the demo application on [http://localhost:4000](http://localhost:4000).

To insert some demo data into the database, you can run the following command:

```bash
docker compose exec app mix ecto.seed
```

## Making changes

After setting up your development environment, you can start making changes to the project. We recommend creating a new branch for your changes. After submitting your changes to your forked repository, you can create a pull request to the `develop` branch of the main repository.
