<img src="https://github.com/naymspace/backpex/blob/develop/priv/static/images/logo.svg" width="100" height="100">

[![CI](https://github.com/naymspace/backpex/actions/workflows/ci.yml/badge.svg)](https://github.com/naymspace/backpex/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/naymspace/backpex/blob/develop/LICENSE.md)
[![Hex](https://img.shields.io/hexpm/v/backpex.svg)](https://hex.pm/packages/backpex)
[![Hex Docs](https://img.shields.io/badge/hex-docs-green)](https://hexdocs.pm/backpex)

# Backpex

Welcome! Backpex is a highly customizable administration panel for Phoenix LiveView applications. Quickly create beautiful CRUD views for your existing data using configurable *LiveResources*. Backpex integrates seamlessly with your existing Phoenix application and provides a simple way to manage your resources. It is highly customizable and can be extended with your own layouts, views, field types, filters and more.

![Backpex Screenshot](https://github.com/naymspace/backpex/blob/develop/priv/static/images/screenshot.png)

<div align="center">
  <a href="https://backpex.live/"><strong>Visit our Live Demo →</strong></a>
</div>

## Learn More

- [Installation](guides/get_started/installation.md)
- [What is Backpex?](guides/about_backpex/what-is-backpex.md)
- [Why we built Backpex?](guides/about_backpex/why-we-built-backpex.md)
- [Contribute to Backpex](guides/about_backpex/contribute-to-backpex.md)

## Key Features

- **LiveResources**: Quickly create LiveResource modules for your database tables with fully customizable CRUD views. Bring your own layout or use our components.
- **Search and Filters**: Define searchable fields on your resources and add custom filters. Get instant results with the power of Phoenix LiveView.
- **Resource Actions**: Add your globally available custom actions (like user invitation or exports) with additional form fields to your LiveResources.
- **Authorization**: Handle authorization for all your CRUD and custom actions via simple pattern matching. Optionally integrate your own authorization library.
- **Field Types**: Many field types (e.g. Text, Number, Date, Upload) are supported out of the box. Easily create your own field type modules with custom logic.
- **Associations**: Handle HasOne, BelongsTo and HasMany(Through) associations with minimal configuration. Customize available options and rendered columns.
- **Metrics**: Easily add value metrics (like sums or averages) to your resources for a quick glance at your date. More metric types are in the making.

## Installation

See our comprehensive [installation guide](guides/get_started/installation.md) for more information on how to install and configure Backpex in your Phoenix application.
