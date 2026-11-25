# Stale-write detection in Ecto and Postgres

Research for [#2572](https://github.com/naymspace/backpex/issues/2572), part of the map
[#2571](https://github.com/naymspace/backpex/issues/2571) (concurrent editing of an item).

**Question:** how can a write detect that the row changed since it was read, and what does each option need from the
user's schema? What does each option catch, how does it fit the neutral write callbacks of
[#2451](https://github.com/naymspace/backpex/pull/2451), and what does Ash offer?

**Versions read:** Ecto 3.14.3, Ecto SQL 3.14.0, Postgrex 0.22.4 (the versions in `mix.lock`, source read from `deps/`),
PostgreSQL 19 docs (current), Ash v3.38.1. Backpex at `a1a8a004` (develop) and the branch `feature/neutral-writes`
of #2451.

## Summary

| Option | Needs from the schema | Catches | Fits `c:update/2` (changeset) | Fits `c:update_all/3` (map) |
| --- | --- | --- | --- | --- |
| `optimistic_lock/3` with a version column | a version column + field, migration | writes that bump the version: Ecto writes through a changeset with `optimistic_lock/3`; any writer if a DB trigger bumps it | yes: a filter on the changeset, result via `:stale_error_field` | no: `update_all` ignores changesets |
| `updated_at` as the lock value | nothing new if the schema has `timestamps()` | writes that set `updated_at`: `Repo.update` with changes; not `update_all`, not plain SQL | yes, via `optimistic_lock/3` with a custom "incrementer" | no |
| conditional `UPDATE … WHERE col = old` | nothing | any writer (Backpex, other app code, SQL) that changed one of the compared columns | not through `Repo.update` (filters are private); needs `update_all` or SQL | yes, if the adapter adds the conditions |
| Postgres `xmin` | a field mapped to the system column | any writer, any column | as a lock field (not verified end to end) | as a condition |

All options are optimistic: the check sits in the `WHERE` of the one `UPDATE`, so it needs no lock and no transaction
around read and write (see "Atomicity" below).

## How Ecto turns a stale write into an error

1. `Ecto.Changeset` has a private `filters` field ("The following fields are private and must not be accessed
   directly": `filters`, … ; [changeset.ex L352-357](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/changeset.ex#L352-L357)).
   `Repo.update/2` adds the primary key to these filters and dumps them into the `WHERE` clause of the `UPDATE`
   ([repo/schema.ex L570, L602-608](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/repo/schema.ex#L570)). The
   Postgres connection renders each filter as `"col" = $n`, or `"col" IS NULL` for `nil`
   ([postgres/connection.ex L335-348](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/postgres/connection.ex#L335-L348)).
2. When the `UPDATE` affects 0 rows, Ecto SQL returns `{:error, :stale}`
   ([sql.ex L1189-1197](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/sql.ex#L1189-L1197)).
   0 rows means "a filter didn't match" or "the row is gone": the two can't be told apart from the result.
3. `Ecto.Repo.Schema` turns `:stale` into ([repo/schema.ex L1059-1087](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/repo/schema.ex#L1059-L1087)):
   - `{:ok, []}` with `allow_stale: true`,
   - `{:error, changeset}` with an error on the field named by `:stale_error_field` (message `:stale_error_message`,
     default `"is stale"`, error metadata `stale: true`),
   - otherwise a raised `Ecto.StaleEntryError`.

   The options are documented for `update/2`, `insert/2` (`:stale_error_field` "only applies to updates"),
   `insert_or_update/2` and `delete/2` ([hexdocs Ecto.Repo.update/2](https://hexdocs.pm/ecto/3.14.3/Ecto.Repo.html#c:update/2)).
4. `Repo.update/2` is a no-op when the changeset has no changes and `:force` is not set: it returns `{:ok, data}`
   without a query ([repo/schema.ex L584, L637-639](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/repo/schema.ex#L584)).
   So a save without changes is never detected as stale.
5. Only the fields in `changes` are written ("Only the fields present in the `changes` part of the changeset are sent to
   the database"; [hexdocs Ecto.Repo.update/2](https://hexdocs.pm/ecto/3.14.3/Ecto.Repo.html#c:update/2)). Without
   detection, two edits of different fields both survive; on the same field the last save wins.

## Option 1: `Ecto.Changeset.optimistic_lock/3` with a version column

**How it works** ([source L3643-3664](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/changeset.ex#L3643-L3664),
[hexdocs](https://hexdocs.pm/ecto/3.14.3/Ecto.Changeset.html#optimistic_lock/3)):

- It reads the current value of the field from the changeset (the value of the item that was read), puts it into
  `changeset.filters`, and adds a `prepare_changes/2` that writes `incrementer.(current)` into the changes. The new
  value is computed only inside the repo, "because we don't want to permanently track the lock change".
- The default incrementer is `+1` with rollover to `1` at `2_147_483_647` (signed 32-bit integer). Other types need a
  custom incrementer, e.g. `fn _ -> Ecto.UUID.generate() end`.
- If the current value is `nil`, it logs a warning and adds **no** filter, so the write is not checked. The docs
  recommend a default: `add :lock_version, :integer, default: 1` and `field :lock_version, :integer, default: 1`.
- It also works for deletes: `optimistic_lock(post, :lock_version) |> Repo.delete()`.

**Needs from the schema:** a column and a schema field, i.e. a migration in the user's app, and a call in the
changeset function (or wherever the changeset is built).

**Catches:** only writes that change the version. Ecto changes it only when a changeset with `optimistic_lock/3` goes
through `Repo.update/2` (or `insert_or_update/2`, `delete/2`). It does not catch:

- other app code that updates the row through a changeset without `optimistic_lock/3`,
- `Repo.update_all/3`, which takes a query and no changeset ([hexdocs Ecto.Repo.update_all/3](https://hexdocs.pm/ecto/3.14.3/Ecto.Repo.html#c:update_all/3)),
- plain SQL.

A database trigger can bump the version for every writer: in a PL/pgSQL row-level `BEFORE` trigger, "Returning a row
value different from the original value of NEW alters the row that will be inserted or updated"
([PostgreSQL: Trigger Functions](https://www.postgresql.org/docs/current/plpgsql-trigger.html)). With a trigger, the
Ecto field needs `read_after_writes: true` to get the new value back ("always read back from the database after
inserts, updates, and deletes"; [schema.ex L677-680](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/schema.ex#L677-L680)).
Not verified here: how a trigger and the incrementer of `optimistic_lock/3` combine (both would bump).

## Option 2: `updated_at` as the lock value

**Precision.** Ecto has four datetime types; `:naive_datetime` and `:utc_datetime` have "a precision of seconds",
the `_usec` variants microseconds ([schema.ex L339-353](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/schema.ex#L339-L353)).
`timestamps()` defaults to `:naive_datetime` ([schema.ex `timestamps/1` options](https://hexdocs.pm/ecto/3.14.3/Ecto.Schema.html#timestamps/1)),
and the autogenerated value of the non-usec types has its microseconds set to 0
([schema.ex L1991-2005](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/schema.ex#L1991-L2005)). The migration
creates `timestamp(0)` for `:naive_datetime`/`:utc_datetime` and `timestamp` (optionally with `:precision`) for the
`_usec` types ([postgres/connection.ex L1819-1833](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/postgres/connection.ex#L1819-L1833)).
Postgres keeps 0 to 6 fractional digits ([PostgreSQL: Date/Time Types](https://www.postgresql.org/docs/current/datatype-datetime.html)).

Consequences:

- With the default second precision, two saves in the same second write the same `updated_at`, so a comparison on
  `updated_at` doesn't see the second one. `_usec` makes this unlikely, not impossible.
- Loading `:utc_datetime` truncates microseconds ([type.ex L721-725](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/type.ex#L721-L725)).
  If the column keeps microseconds but the field is a non-usec type, the loaded value never equals the stored one, so
  a filter on it would always report stale (inferred from the source, not tested).

**With Ecto:** `optimistic_lock/3` accepts any field and incrementer, so `optimistic_lock(changeset, :updated_at, fn _ ->
now end)` makes `updated_at` the lock. The incrementer's value lands in `changes`, and Ecto autogenerates only the
fields not already in `changes` ([repo/schema.ex L1315-1328](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/repo/schema.ex#L1315-L1328)).
This is derived from the source; Ecto documents the incrementer only for version values.

**Needs from the schema:** nothing new if the schema has `timestamps()`; a `_usec` type for useful precision, which
is a migration for most existing apps.

**Catches:** writes that set `updated_at`. `Repo.update/2` sets it when the changeset has changes. `update_all` "will
not update autogenerated fields like the `updated_at` columns" ([repo.ex L1569-1570](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/repo.ex#L1569-L1570)),
and plain SQL sets it only if the statement or a trigger does. A Backpex soft delete via `update_all` (e.g.
`%{deleted_at: now}` in #2451) would not change `updated_at`.

## Option 3: conditional `UPDATE … WHERE <columns> = <old values>`

**How it works:** the `UPDATE` repeats the values the admin saw for some columns, e.g. the fields of the form, and
counts the affected rows. 0 rows: something changed one of those columns, or the row is gone.

**Needs from the schema:** nothing. It needs the old values, which Backpex has: the form changeset is built on the
item of the mount (`changeset.data`), and `changeset.changes` names the fields the admin changed.

**With Ecto:**

- `Repo.update/2` can't take arbitrary conditions: `filters` is private ([changeset.ex L352-357](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/changeset.ex#L352-L357)),
  and `optimistic_lock/3` is the only public function that sets it. One `optimistic_lock/3` call per field would add the
  filter, but also write the incrementer's value into that field, so it is no general mechanism.
- `Repo.update_all/3` takes any query: `from(p in Post, where: p.id == ^id and p.title == ^old_title) |> repo.update_all(set: changes)`
  returns `{count, _}`. It skips everything `Repo.update/2` does: no changeset, so no validations, no
  `prepare_changes`, no associations or embeds, no autogenerated `updated_at` ([repo.ex L1569-1570](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/repo.ex#L1569-L1570)),
  no constraint errors on the changeset.

**Caveats of comparing values:**

- `nil` needs `is_nil/1` in an Ecto query: comparing with `nil` raises "comparison with nil is forbidden as it is unsafe" ([query/builder.ex L381-384](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/query/builder.ex#L381-L384)); the changeset filters handle `nil` as `IS NULL`
  ([postgres/connection.ex L343-344](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/postgres/connection.ex#L343-L344)).
- The compared value must be the value as stored. The truncation on load above (Option 2) applies to every column with a non-usec datetime type.
  Not checked here: equality of `json` (as opposed to `jsonb`), floats, arrays, embeds and custom types.

**Catches:** every writer that changed one of the compared columns: Backpex, other app code, SQL. It ignores changes
to other columns, so it can detect conflicts per field instead of per row (the scope is a design decision).

## Option 4: Postgres `xmin` (side note)

`xmin` is a system column: "The identity (transaction ID) of the inserting transaction for this row version. (A row
version is an individual state of a row; each update of a row creates a new row version for the same logical row.)"
So it changes on every `UPDATE` of the row, from any writer. Caveats from the same page: transaction IDs are 32-bit
and wrap around, and "It is unwise, however, to depend on the uniqueness of transaction IDs over the long term (more
than one billion transactions)" ([PostgreSQL: System Columns](https://www.postgresql.org/docs/current/ddl-system-columns.html)).
Postgrex encodes and decodes the `xid` type as an integer in `0..4_294_967_295` ([postgrex oid.ex](https://github.com/elixir-ecto/postgrex/blob/v0.22.4/lib/postgrex/extensions/oid.ex)).
Not verified: reading `xmin` through an Ecto schema field (`source: :xmin`) and using it with `optimistic_lock/3`.
It is Postgres-only.

## Atomicity: why the check belongs in the `UPDATE`

Read Committed is the default isolation level of Postgres. An `UPDATE` that finds a row changed by a concurrent
transaction waits for it; if that transaction commits, "The search condition of the command (the WHERE clause) is
re-evaluated to see if the updated version of the row still matches the search condition"
([PostgreSQL: Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)). So a version or
value condition in the `WHERE` is checked against the latest committed row, without a race between check and write.
A check in Elixir before the write (e.g. comparing a re-read item, as the re-read of
[#2525](https://github.com/naymspace/backpex/pull/2525) could) leaves a window between read and `UPDATE`.

## How Backpex writes today

- The edit form saves with `Backpex.Resource.update/6` on `socket.assigns.item`, the item of the mount
  ([form_component.ex L326-371](../lib/backpex/live_components/form_component.ex)). `index_editable` saves through
  `Backpex.Resource.update/6` too ([index.ex L584](../lib/backpex/live_resource/index.ex),
  [field.ex L749](../lib/backpex/field.ex)), on the item of the list.
- `Backpex.Resource.update/6` builds the changeset with `change/6` (the LiveResource's `update_changeset`), runs
  `before_save_fun` (`on_item_updating/2`) and calls `adapter.update(changeset, live_resource)`
  ([resource.ex L217-237](../lib/backpex/resource.ex)).
- The Ecto adapter calls `repo.update(changeset)` with no options ([adapters/ecto.ex L299-303](../lib/backpex/adapters/ecto.ex)).
  If a user's `update_changeset` calls `optimistic_lock/3` today, a stale save raises `Ecto.StaleEntryError` in the
  LiveView. Backpex has no reference to `StaleEntryError`, `optimistic_lock` or `:stale_error_field` (searched `lib/`,
  `demo/lib`, `integration_test/`, `guides/`).
- The form handles `{:error, changeset}` by showing the changeset's errors
  ([form_component.ex L361-370](../lib/backpex/live_components/form_component.ex)), so a `:stale_error_field` error
  would show like a validation error, on a field the form may not render.

## Fit with the neutral writes of #2451

On `feature/neutral-writes`:

- `c:update/2` takes an `Ecto.Changeset` ("the form type of Backpex for every data source") and returns
  `{:ok, item} | {:error, Ecto.Changeset.t() | term()}`.
- `c:update_all/3` takes items and a map of changes (`%{deleted_at: now}`) and returns `{:ok, count}`; the Ecto adapter
  runs `repo.update_all(set: Map.to_list(changes))` on the primary keys.
- `Backpex.Adapters.Memory.update/2` stores `Ecto.Changeset.apply_action(changeset, :update)`; it doesn't look at the
  changeset's filters, and its `update_all/3` applies the changes to the stored items "so these keep what others
  changed since `items` were read".

What follows for each option:

- **Version column / `updated_at` via `optimistic_lock/3`:** it travels inside the changeset, so `c:update/2` needs no
  new argument. The Ecto adapter needs to pass `stale_error_field:` (or rescue `StaleEntryError`) to turn the conflict
  into a return value; a distinct result such as `{:error, :stale}` would need a new return of `c:update/2`, as the
  error metadata `stale: true` on the changeset error is the only marker Ecto gives. Other adapters see an Ecto
  changeset with a private `filters` field: the Memory adapter ignores it today, so an adapter-neutral design names
  the lock (e.g. a field of the LiveResource) instead of relying on `filters`.
- **Conditional update on old values:** the old values are `changeset.data` and the fields are the keys of
  `changeset.changes`, so a neutral `c:update/2` has them already. The Ecto adapter can't pass them to `Repo.update/2`
  (private `filters`); it would need `update_all` (and lose what `Repo.update/2` does) or one `optimistic_lock/3`
  per lock field. For `c:update_all/3`, conditions would be a new argument (a neutral map of expected values, no
  query, in line with "extension points never receive the adapter's query").
- **0 rows is ambiguous** in every option: the adapter can tell "changed" from "deleted" only with a second read.
- **Associations:** `Repo.update/2` writes changed children through the same changeset in one transaction, but the
  filters apply to the parent's `UPDATE` only. A parent without changes of its own is not updated (no-op), so a lock
  on the parent isn't checked when only children change (from the update flow in
  [repo/schema.ex L584-639](https://github.com/elixir-ecto/ecto/blob/v3.14.3/lib/ecto/repo/schema.ex#L584-L639); not tested).

## Ash (side note)

`Ash.Resource.Change.OptimisticLock` ([source](https://github.com/ash-project/ash/blob/v3.38.1/lib/ash/resource/change/optimistic_lock.ex),
[docs](https://ash.hexdocs.pm/Ash.Resource.Change.OptimisticLock.html)), used through the builtin
`optimistic_lock/1`:

- It allows an update or destroy "only if the version of a record that you have in memory is the same as the version
  in the database", and increments the version on success.
- Non-atomic path: `Ash.Changeset.filter(changeset, {attribute, [eq: current]})` plus an increment by 1.
- Atomic path: an expression that sets `attribute + 1` if it equals the old value and otherwise raises
  `Ash.Error.Changes.StaleRecord`. On an update of a query (no original record) it returns `:not_atomic`: "Cannot use `optimistic_lock` when updating a query, because we must know the previous version."
- `Ash.Changeset.filter/2` is public and takes any expression ("Adds a filter for a record being updated or
  destroyed"), so the conditional update of Option 3 also exists in Ash. AshPostgres returns
  `Ash.Error.Changes.StaleRecord` when the filter doesn't match.

For the design: Ash has the same two shapes (version attribute, conditions on the old record) and one error type, so
a neutral "expected state" passed to the adapter doesn't rule Ash out. An Ash resource configures its lock itself, in
the resource's action, not in a changeset function Backpex builds.

## Open points (not answered here)

- Whether the lock is per row (version, `updated_at`, `xmin`) or per field (old values of the form's fields).
- Whether Backpex requires a version column, reads one the user names, or works without schema change.
- `json`/float/array/embed equality for Option 3, `xmin` through Ecto, trigger plus incrementer: not verified.
