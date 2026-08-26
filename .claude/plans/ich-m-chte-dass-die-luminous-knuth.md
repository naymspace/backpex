# Centralized Authorization Enforcement via Backpex.Authorization + Action Gates

> Incorporates the review from MR !731 (Flo, 2026-08-18): new `Backpex.Authorization` module, gate **before** `change/6`, option names `authorization_action:`/`authorize?:`, upgrade guide `v0.21.md`, hardened item-ID entry points, key resolver without `String.to_existing_atom`, updated line references.

## Context

Authorization (`can?/3`) is currently checked exclusively by the **callers** in the LiveView layer — partly only at mount time (`form.ex`), partly not at all at execution time. Concrete gaps:

- `Backpex.Resource` (lib/backpex/resource.ex) contains **not a single** `can?` call; `insert/update/delete_all/update_all` blindly trust the caller.
- Item actions silently filter out unauthorized items (`item_action.ex:271-275`, `form_component.ex:389`) — `handle/3` runs even with an empty list and reports success.
- Resource actions are only checked when the modal opens (`index.ex:498`), **not on submit** (`form_component.ex:307-356`).
- `:new`/`:edit` saves are only checked at mount, not at `Resource.insert/update` time.
- On modal submit, the action key is read from the **DOM parameter** (`form_component.ex:182/199`) — the `can?` check runs against the client-supplied key while the server-side module executes → **actively bypassable, classify as a security fix** (not just "forgettable").
- `handle_event("update-selected-items", ...)` (`index.ex:200`) accepts forged IDs → `nil` lands in `selected_items` and reaches user `can?` during render.

**Goal:** Authorization is enforced centrally and can no longer be forgotten or bypassed.

**Decisions made (user + review):**
1. Enforcement in `Backpex.Resource` (all mutations) **plus** hard gates directly before `action.module.handle` (actions run arbitrary code that doesn't necessarily write through `Backpex.Resource`).
2. **Strict**: a single unauthorized item in a selection → `Backpex.ForbiddenError` (403). No more silent filtering. (= Ash `access_type :strict`; right for an admin UI, the button gets disabled anyway.)
3. Breaking changes to `Backpex.Resource` are OK, documented in an upgrade guide (the module is marked "under heavy development", Backpex is pre-1.0).
4. **Review:** checks live in a dedicated `Backpex.Authorization` module — `can?`-style functions are for the UI (preflight), `authorize!`-style functions are the execution gate. Attachment point for a future authorizer behaviour.
5. **Review:** the gate runs **before `Resource.change/6`** — `Resource` is not a context module, but in a default Phoenix app authorization happens in the context function that wraps both changeset and DB access. `persist_item` runs user code (changeset, `before_changeset/6`) before the adapter, so gating "before the adapter call" is too late. `Resource.change/6` itself stays ungated (live validation!).

## Design cornerstones

- **Authorization-action mechanism**: each mutation authorizes against a default action (`insert`→`:new`, `update`→`:edit`, `delete_all`→`:delete`, `update_all`→`:edit`), overridable via `opts[:authorization_action]` (review: more explicit than `action_key`, which mentally collides with `opts[:action]` in `change/6`). Item-action code receives the correct key through a new assign `assigns.item_action_key`, set immediately before `action.module.handle/3`.
- **Escape hatch**: `authorize?: false` option on all four mutations (for system/cascade writes, e.g. the demo's post nullification across another resource). Explicit and greppable. Simple `is_boolean` validation.
- **`can?` conventions**: `insert` checks `can?(assigns, action, nil)` (consistent with all existing `:new` checks; prevents a silent-allow hole for user clauses matching `nil`). `update` checks with the item; `delete_all`/`update_all` per item. For item actions, **no** key-level check with `nil` is introduced (would crash user pattern matches expecting a struct).
- **Failure semantics**: unauthorized → `Backpex.ForbiddenError`; `nil` item (stale/forged id) → `Backpex.NoResultsError` (404 semantics — anti-enumeration; `nil` never reaches user `can?`); unknown action key → `NoResultsError`; empty selection → no-op (`handle/3` is never called with `[]`).
- **Key resolution without `String.to_existing_atom`** (review): today a forged key raises `ArgumentError` before any `NoResultsError`. Resolve client-supplied keys by comparing the binary against the registered action keys (`item_actions`/`resource_actions`); unknown → `NoResultsError`. Applies to `index.ex:294`, `show.ex:77`, `index.ex:493-495`.
- Reads (`list/get/count`) remain ungated (`:index`/`:show` stay enforced in the view layer; filtering after pagination would corrupt counts/select-all) — documented. The adapter behaviour stays untouched (adapter callbacks have no assigns).

## Steps

### 1. New module `Backpex.Authorization` (`lib/backpex/authorization.ex`)
Public API (under the hood everything calls `live_resource.can?(assigns, action, item)`):
```elixir
Backpex.Authorization.can?(live_resource, assigns, action, item)        # preflight (UI)
Backpex.Authorization.can_all?(live_resource, assigns, action, items)   # preflight, all items
Backpex.Authorization.authorize!(live_resource, assigns, action, item)  # gate: ForbiddenError
Backpex.Authorization.authorize_all!(live_resource, assigns, action, items) # gate per item; nil item → NoResultsError
```
Refactor the existing raise sites to use it (`index.ex:498`, `form.ex:96-106`, `show.ex:64`; `maybe_handle_item_action` follows in Step 4). Extend the `c:can?/3` doc (live_resource.ex) to describe enforcement. This module is the future attachment point for an authorizer behaviour (Ash-style `Authorizer` split — explicitly **not now**).

### 2. New `Backpex.Resource` API (`lib/backpex/resource.ex`)
- `insert/6` and `update/6` (both `opts \\ []`): **gate at the top of `insert`/`update`**, before `change/6`/`before_changeset` run (review #2 — not inside `persist_item`):
  - `{authorize?, opts} = Keyword.pop(opts, :authorize?, true)` (validate `is_boolean`), `{authorization_action, opts} = Keyword.pop(opts, :authorization_action, default)` (`insert`→`:new`, `update`→`:edit`)
  - when `authorize?`: `Backpex.Authorization.authorize!(live_resource, assigns, authorization_action, can_item)` with `can_item = nil` for insert, otherwise `item`.
  - `:authorization_action`/`:authorize?` are popped before the remaining opts reach `change/6`.
  - `Resource.change/6` itself stays ungated (live validation).
- **Breaking:** `delete_all(items, live_resource)` → `delete_all(items, assigns, live_resource, opts \\ [])` with guard `is_list(items) and is_map(assigns) and is_atom(live_resource)`; default action `:delete`; `authorize_all!` (nil item → `NoResultsError`).
- **Breaking:** `update_all(items, updates, event_name \\ "updated", live_resource)` → `update_all(items, updates, assigns, live_resource, opts \\ [])`; `event_name` moves into opts; same guard. **The `is_map(assigns)` guard is load-bearing**: the old 4-arity call (`update_all(items, updates, "deleted", Mod)`) collides with the new arity and must fail loudly with a `FunctionClauseError` instead of silently "authorizing" against a string.
- An empty item list passes vacuously (nothing to authorize; the view gates no-op beforehand).
- Update moduledoc/`@doc`s (replace the `TODO: docs`): `:authorization_action`, `:authorize?`, `:event_name`, note that reads are not gated. No `iex>` doctests (test/doc_test.exs:7 runs doctests for this module).

### 3. Strict gate in `Backpex.ItemAction` (`lib/backpex/item_actions/item_action.ex:265-289`)
- Delegate to `Backpex.Authorization.authorize_all!/4` (per item; `nil` → `NoResultsError`).
- `handle_item_action/5`: replace the filter with the gate (hard, directly before `handle`); when `items == []` only `after_handle.(socket)` (never `handle(socket, [], _)`); otherwise `assign(socket, :item_action_key, key)` and call `handle` with the **full** list. Adjust the `@doc` (currently advertises filtering) and document `assigns.item_action_key`.

### 4. View-layer gates + entry-point hardening
- **`lib/backpex/live_resource/index.ex`**:
  - `handle_event("item-action", %{"item-id" => ...})` (:132): `find_item_by_primary_value(...) || raise(Backpex.NoResultsError)` before the item enters the selection.
  - `handle_event("update-selected-items", ...)` (:200) (review #3): validate the ID — forged/stale ID must not put `nil` into `selected_items` (would reach user `can?` during render). Validate **all** item-ID entry points, not just `item-action`.
  - `maybe_handle_item_action/2` (:293): resolve the key against registered item actions (no `String.to_existing_atom`); unknown key → `NoResultsError`; then `Backpex.Authorization.authorize_all!(live_resource, socket.assigns, key, items)` **before** the `has_confirm_modal?` branch (the modal never opens for an unauthorized selection; the Step 3 gate stays as defense in depth).
- **`lib/backpex/live_resource/show.ex`** `maybe_handle_item_action/2` (:76-86): same resolver + `authorize_all!` with `[item]`.
- **`lib/backpex/live_components/form_component.ex`**:
  - `handle_event("save", %{"action-key" => ...})` (:182, :199): ignore the DOM param, take the key server-side from `socket.assigns.action_to_confirm.key` (set at index.ex:308 / show.ex:96); remove `phx-value-action-key`. Classification: hardening — no bypass remains once central enforcement is in place, but today this is the active bypass (see Context).
  - `handle_form_item_action/3` (:358-397): replace the filter (:389); `authorize_all!` **before** changeset validation; on empty selection no-op (clear selected_items, `push_navigate(to: return_to)`); otherwise call `handle` with `assign(socket, :item_action_key, action_key)` and the full list.
  - `handle_save(socket, :resource_action, ...)` (:307): at the top, `Backpex.Authorization.authorize!(live_resource, assigns, assigns.resource_action_id, nil)` — closes the submit window (the gate at index.ex:498 stays). `resource_action_id` verifiably reaches the component via `Map.drop(assigns, ...)` in resource_index.html.heex:15.

### 5. Index-editable cleanup (`lib/backpex/field.ex:424-453`)
Remove the manual check at :427-429 — `Resource.update/6` now enforces `:edit` with identical assigns/item at the same effective point (avoids evaluating user `can?` twice per inline edit). Behavior (raise on forged `update-field` events) unchanged.

### 6. Built-in Delete action (`lib/backpex/item_actions/delete.ex:44-61`)
- `Resource.delete_all(items, socket.assigns, live_resource, authorization_action: Map.get(socket.assigns, :item_action_key, :delete))` — correct even when registered under a custom key.
- In the existing `rescue`: `error in [Backpex.ForbiddenError] -> reraise error, __STACKTRACE__` as the first clause — the blanket rescue must not turn the defense-in-depth check into a flash message.

### 7. UI alignment (`lib/backpex/html/resource.ex:975`, call site :898)
`action_disabled?/3`: disable the toolbar button when the selection is empty **or** any item is unauthorized. **Handle the `Enum.all?([]) == true` pitfall explicitly** (review): `items == [] or not Enum.all?(items, &can?/…)` — matching the strict semantics (a mixed selection would now raise). Use `Backpex.Authorization.can_all?/4` for the item check.

### 8. Demo migration (`demo/lib/demo_web/item_actions/user_soft_delete.ex`)
- :71 → `Backpex.Resource.update_all(items, updates, socket.assigns, socket.assigns.live_resource, authorization_action: socket.assigns.item_action_key, event_name: "deleted")`
- :77 (cross-resource cascade onto `DemoWeb.PostLive` — the canonical escape-hatch case) → `..., socket.assigns, DemoWeb.PostLive, event_name: "updated", authorize?: false)`
- Demo soft-delete `rescue`: same `reraise ForbiddenError` treatment as Step 6.
- Demo `can?` audit (verified): `film_review_live` removes the delete action entirely; `short_link_live` denies `:delete` with the action still registered (forged events now raise — desired); `user_live` denies `:user_soft_delete` for admins and **relied on silent filtering** for select-all → with Step 7 the button is now disabled for mixed selections, forged events raise.

### 9. Docs
- **New upgrade guide `guides/upgrading/v0.21.md`** (review #1: v0.20.0 is released, `v0.20.md` already exists; mix.exs is at 0.20.0), register in `mix.exs` `extras()`. Contents:
  - **Declare the DOM `action-key` fix as a security fix**: today the `can?` check uses the client-supplied key while the server-side module executes — actively bypassable, not just "forgettable".
  - Both signature changes with before/after; the `FunctionClauseError` note for the old `update_all/4` arity.
  - Central enforcement + default actions + `authorization_action:`/`authorize?: false`/`item_action_key`; `insert` checks with `nil`.
  - Strict item-action behavior (raise instead of filter, button disable, `NoResultsError` for unknown items/keys, DOM `action-key` ignored), snapshot staleness, double-click → `NoResultsError`.
  - Checklist for custom actions; note on the `handle_item_action/5` behavior change (public function).
- `guides/authorization/live-resource-authorization.md`: new "Enforcement" section (where checks run, strict semantics, escape hatch, reads ungated, `Backpex.Authorization` API).
- `guides/actions/item-actions.md`: **fix the stale `update_all` example at ~:187** (matches no signature that ever existed; its `rescue` is also syntactically broken and would swallow `ForbiddenError`) + add an "Authorization" section.
- `guides/actions/resource-actions.md`: add an "Authorization" note (gate at open + submit; `Resource` calls inside `handle/2` default to `:new`/`:edit` → pass `authorization_action:`/`authorize?: false` where needed).

### 10. Tests
**Library (host: `mix test`; no DB access):**
- New `test/backpex/authorization_test.exs`: unit tests for `can?/can_all?/authorize!/authorize_all!` (fake live resources `AllowAll`/`DenyAll`/`KeyAware`; `nil` item in `authorize_all!` → `NoResultsError`).
- New `test/backpex/resource_test.exs`: hand-rolled fixtures (no `use Backpex.LiveResource` needed — `Resource` only calls `config(:adapter)`, `can?/3`, `pubsub/0`): `StubAdapter` (sends `{:adapter, fun}` to the test pid → `refute_received` proves "adapter never touched on denial"), `start_supervised({Phoenix.PubSub, ...})` for broadcast assertions. Cases: **denial raises before `change/6`/`adapter.change`** (review); success + broadcast; `authorization_action:` override; `insert` passes `nil` to `can?`; `authorize?: false`; **`:authorization_action`/`:authorize?` never reach `change/6`** (review); `delete_all` with one forbidden item raises entirely; `nil` in the list → `NoResultsError`; `[]` passes; **old `update_all` arity → `assert_raise FunctionClauseError`**.
- New `test/backpex/item_action_test.exs`: socket built directly, fixture action sends `{:handled, items}`: all authorized → full list + `item_action_key` set; one forbidden → `ForbiddenError` + `refute_received`; `nil` → `NoResultsError`; `[]` → `handle` not called, `after_handle` is.

**Demo integration (`docker compose exec -T app mix test`):**
- Forged `item-action` event (row, no form) on short links (`can?(:delete) == false`): `catch_exit` with `%Backpex.ForbiddenError{}`, record still exists.
- Forged event for an admin user with `user_soft_delete` (modal path): `ForbiddenError` at the modal-open gate, `deleted_at` stays `nil`.
- Mixed selection (admin + non-admin): (a) toolbar button renders `disabled`, (b) forged bulk event → `ForbiddenError`, nobody soft-deleted.
- Forged event with a nonexistent `item-id` → exit with `%Backpex.NoResultsError{}`.
- **Forged `update-selected-items` IDs** (review): no `nil` in `selected_items`, no crash in user `can?`.
- **Forged/unknown action key** (review): `NoResultsError`, no `ArgumentError` from `String.to_existing_atom`.
- **Permission revoked between modal open and submit** (review): submit gate raises `ForbiddenError`.
- **Rescues don't swallow `ForbiddenError`** (review): built-in Delete + demo soft-delete.
- Regression: existing `soft_delete_item_action_live_test.exs`, film-review/short-link tests must pass after Step 8 (they now exercise the new signature, `item_action_key`, and `authorize?: false` end-to-end).

## Sequencing (per review)

1. `Backpex.Authorization` + unit tests.
2. `Resource` enforcement (gate before `change/6`) + library tests → library compiles, tested standalone.
3. Key resolver + hardening of all item-ID entry points (Step 4 entry points).
4. Action gates + server-side dispatch (Steps 3, 4, 6).
5. UI alignment (Step 7), remove duplicate check (Step 5).
6. Demo migration (Step 8) → demo suite in docker.
7. Demo integration tests (Step 10).
8. Guides + `v0.21.md` (Step 9).
9. `mix format` + `mix lint` (host), `docker compose exec -T app mix test` + `docker compose exec -T app bun run lint` (demo).

## Risks / edge cases

- **`insert` must check with `nil`**, otherwise a silent-allow hole for user clauses like `can?(_, :new, nil)` with a permissive catch-all.
- **Do not omit the `is_map(assigns)` guard on `update_all`** — the most dangerous collision (same arity, different argument meaning).
- **Gate placement matters** (review): `before_changeset/6` and the changeset are user code — authorizing only "before the adapter" would run user code for unauthorized requests. Gate at the top of `insert`/`update`.
- `Delete.handle`'s `rescue` would swallow `ForbiddenError` without the `reraise`; the custom-action example in item-actions.md and the demo soft-delete have the same pattern → fix all three.
- Snapshot staleness: `can?` checks against items loaded at render time; no re-fetch between modal open and submit (same as today; document + test the revocation window at the submit gate).
- Double-click after deletion: now `NoResultsError` (LV crash + reconnect) instead of a "0 items deleted" flash — deliberate trade-off, mention in the upgrade guide.
- `Enum.all?([]) == true`: empty selection must disable the button explicitly (Step 7).

## Deliberately deferred (review "Later, not now")

- Pull `can?/3` behind a small authorizer behaviour (= Ash's `Authorizer`/`Policy.Authorizer` split) — `Backpex.Authorization` is the attachment point.
- Explicit actor instead of full `assigns`.
- Optional strict mode (deny-by-default). No policy DSL, no query filtering, no `:maybe`.
