# Prerequisites

Backpex integrates seamlessly with your existing Phoenix LiveView application, but there are a few prerequisites you need to meet before you can start using it.

## Phoenix LiveView

Backpex is built on top of Phoenix LiveView, so you need to have Phoenix LiveView installed in your application. If you generate a new Phoenix application using the latest version of the `mix phx.new` generator, Phoenix LiveView is included by default.

## Alpine.js

Backpex uses [Alpine.js](https://alpinejs.dev/) for some interactivity. Make sure you have Alpine.js installed in your application.

You can install Alpine.js by installing it via npm:

```bash
cd assets && npm install alpinejs
```

Then, import Alpine.js in your `app.js` file, start it and adjust your LiveView configuration:

```javascript
import Alpine from "alpinejs";

window.Alpine = Alpine;
Alpine.start();

const liveSocket = new LiveSocket('/live', Socket, {
  // add this
  dom: {
    onBeforeElUpdated (from, to) {
      if (from._x_dataStack) {
        window.Alpine.clone(from, to)
      }
    },
  },
  params: { _csrf_token: csrfToken },
})
```

## Tailwind CSS

Backpex uses Tailwind CSS for styling. Make sure you have Tailwind CSS installed in your application. You can install Tailwind CSS by following the [official installation guide](https://tailwindcss.com/docs/installation). If you generate a new Phoenix application using the latest version of the `mix phx.new` generator, Tailwind CSS is included by default.

## daisyUI

Backpex is styled using daisyUI. Make sure you have daisyUI installed in your application. You can install daisyUI by following the [official installation guide](https://daisyui.com/docs/install/).

## Ecto

Backpex currently depends on Ecto as the database layer. Make sure you have a running Ecto repository in your application.

> #### Warning {: .warning}
>
> Backpex requires a single primary key field in your database schema. Compound keys are not supported. We tested Backpex with UUID (binary_id) and integer (bigserial) primary keys. They need to be URL-safe.

If you meet all these prerequisites, you are ready to install and configure Backpex in your Phoenix application. See our [installation guide](guides/get_started/installation.md) for more information on how to install and configure Backpex.
