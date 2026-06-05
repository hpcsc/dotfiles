# Elixir Performance Patterns

## Data Structure Choices

### Lists: prepend, never append in loops

List append (`++`) copies the entire left operand. Build by prepending, reverse once at the end.

```elixir
# Bad: O(n²) — each append copies the accumulator
Enum.reduce(items, [], fn item, acc -> acc ++ [transform(item)] end)

# Good: O(n) — prepend then reverse
items
|> Enum.reduce([], fn item, acc -> [transform(item) | acc] end)
|> Enum.reverse()

# Best: Enum.map already does this
Enum.map(items, &transform/1)
```

### `length/1` is O(n)

Never use it for emptiness checks — pattern match instead.

```elixir
# Bad: walks the whole list to learn it isn't empty
if length(list) > 0, do: ...

# Good: constant time
case list do
  [] -> ...
  [_ | _] -> ...
end

# Also fine
if list == [], do: ...
match?([_ | _], list)
```

### Maps for lookup, keyword lists for small options

Keyword list access is a linear scan. Anything used as a lookup table beyond a handful of entries should be a map; membership checks on large collections belong in a `MapSet`.

```elixir
# Bad: O(n) membership test inside a loop → O(n·m)
Enum.filter(events, fn e -> e.id in allowed_ids_list end)

# Good: O(1) membership
allowed = MapSet.new(allowed_ids_list)
Enum.filter(events, fn e -> MapSet.member?(allowed, e.id) end)
```

---

## Enum, Stream, and Pipelines

### Each Enum stage materializes a full list

A long `Enum` pipeline over a large collection allocates an intermediate list per stage. Use `Stream` for lazy composition over large/unbounded data, or collapse stages into one `reduce`.

```elixir
# Bad: three full intermediate lists for a million rows
huge_list |> Enum.map(&parse/1) |> Enum.filter(&valid?/1) |> Enum.take(100)

# Good: lazy — stops after 100 results, no intermediates
huge_list |> Stream.map(&parse/1) |> Stream.filter(&valid?/1) |> Enum.take(100)
```

For small collections, plain `Enum` is faster and clearer — `Stream` adds per-element overhead. Reach for it on size, not by default.

---

## Strings and Binaries

### Build output as iodata, not by concatenation

Binary concatenation in a loop copies the accumulated binary every iteration. IO lists are O(1) to build and the VM writes them without flattening.

```elixir
# Bad: O(n²) copying
Enum.reduce(rows, "", fn row, acc -> acc <> render(row) <> "\n" end)

# Good: iodata — nested lists are fine, no copying
rows |> Enum.map(fn row -> [render(row), ?\n] end) |> IO.iodata_to_binary()
```

Anything headed for a socket, file, or response body can stay as iodata — skip `IO.iodata_to_binary` entirely.

### Large-binary retention

Matching a slice out of a large binary creates a sub-binary that **references the original**, keeping the whole thing alive. When retaining small slices of large payloads (parsing uploads, message bodies), copy them out:

```elixir
header = :binary.copy(binary_part(payload, 0, 32))
```

### Never `String.to_atom/1` on external input

The atom table is never garbage collected — unbounded atom creation is a memory leak and a DoS vector. Use `String.to_existing_atom/1` or an explicit allowlist mapping.

---

## Processes

### A single GenServer is a serial bottleneck

Every call queues through one mailbox. A GenServer fronting read-heavy shared data caps throughput at one core.

```elixir
# Bad: every reader serialized through the server
def handle_call({:get, key}, _from, state), do: {:reply, Map.get(state.cache, key), state}

# Good: readers hit ETS concurrently; the server only writes
:ets.new(:cache, [:named_table, :set, :protected, read_concurrency: true])
```

Symptoms: rising message queue length on one pid. Don't funnel a hot path through a process that exists only for code organization.

### Bound your parallelism

`Task.async_stream/3` with explicit `max_concurrency` for fan-out over collections — spawning one task per element of an unbounded collection stampedes downstream services and exhausts resources.

---

## I/O & Networking

### Always set HTTP client timeouts and reuse pools

Connection pools (Finch, Req's default pool, hackney pools) are defeated by creating ad-hoc clients per call. Configure connect/receive timeouts explicitly — defaults can be infinite or far too generous for a request path.

```elixir
# Good: named pool, explicit timeouts, reused across calls
Finch.start_link(name: MyApp.Finch, pools: %{default: [size: 25]})
Req.get!(url, finch: MyApp.Finch, connect_options: [timeout: 2_000], receive_timeout: 5_000)
```

Retry loops need max attempts and backoff — never unbounded retries on a request path.

### Ecto: query shape dominates

- **N+1**: `preload` associations in the query, never load them per row in a loop
- **Large result sets**: `Repo.stream/2` inside a transaction, or keyset pagination — never `Repo.all` an unbounded table
- **Narrow selects**: `select: [:id, :status]` when you don't need full schemas
- **Bulk writes**: `Repo.insert_all/3` (or `Ecto.Multi`) over per-row `Repo.insert` in a loop
- Every list endpoint query has a `limit`

---

## Profiling First

**Never optimize without measuring.** The BEAM has excellent tooling:

```bash
# Micro-benchmarks (add benchee as a dev dependency)
mix run bench/my_bench.exs

# Built-in profilers
mix profile.eprof -e 'MyApp.hot_function()'   # time per function
mix profile.fprof -e 'MyApp.hot_function()'   # call graph, heavier
mix profile.tprof -e 'MyApp.hot_function()'   # unified profiler (OTP 27+)
```

Live systems: `:observer.start()` for process/memory overview, `:recon` for message-queue and binary-leak hunting, telemetry metrics for trends.

### Benchmark correctly

```elixir
Benchee.run(
  %{
    "iodata" => fn -> render_iodata(rows) end,
    "concat" => fn -> render_concat(rows) end
  },
  inputs: %{"1k rows" => rows_1k, "100k rows" => rows_100k}
)
```

Use realistic input sizes — list/binary asymptotics only show at scale.

---

## Review Checklist

When reviewing Elixir code for performance issues, check:

- [ ] No list `++` appends or binary `<>` concatenation inside loops/reduce
- [ ] No `length/1` for emptiness checks
- [ ] Lookup tables are maps/MapSets, not lists scanned with `in`/`Enum.member?`
- [ ] Large-collection pipelines use `Stream` or a single `reduce`, not stacked `Enum` stages
- [ ] Output built as iodata where it feeds I/O
- [ ] Retained slices of large binaries copied with `:binary.copy`
- [ ] No `String.to_atom` on external input
- [ ] No read-heavy hot path serialized through a single GenServer (ETS with `read_concurrency` instead)
- [ ] Fan-out bounded with `max_concurrency`
- [ ] HTTP clients use shared pools with explicit connect/receive timeouts; retries bounded with backoff
- [ ] Ecto: preloads for associations, streams/pagination for large sets, `insert_all` for bulk writes, limits on list queries
- [ ] Claims of "performance improvement" backed by Benchee or profiler data
