# Elixir Concurrency Patterns

## Process Lifecycle

### Supervise everything

Every long-lived process belongs in a supervision tree. Bare `spawn/1` orphans work; crashes vanish silently.

```elixir
# Bad: unsupervised fire-and-forget — crashes are invisible, no shutdown path
spawn(fn -> deliver_email(email) end)

# Good: supervised, observable, shut down cleanly with the app
Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> deliver_email(email) end)
```

### `Task.async` links to the caller

`Task.async/1` links the task to the spawning process — an unhandled crash in the task brings the caller down, and every `async` must be matched with an `await`/`yield`. For fire-and-forget from a request process, use `Task.Supervisor.async_nolink/2` or `start_child/2`.

```elixir
# Bad: task crash kills the request process; result never awaited
Task.async(fn -> log_analytics(event) end)

# Good: failure isolated from the caller
Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn -> log_analytics(event) end)
```

### In tests, `start_supervised!/1`

ExUnit owns the lifecycle and guarantees ordered shutdown between tests — no leaked named processes.

---

## GenServer Call Discipline

### Don't block the server loop

A `handle_call` doing slow I/O blocks **every** caller of that server. Move slow work to a Task and reply later, or use `handle_continue` for post-init work.

```elixir
# Bad: every caller queues behind this HTTP call
def handle_call({:enrich, item}, _from, state) do
  {:reply, ExternalAPI.enrich(item), state}
end

# Good: server stays responsive; reply when the work completes
def handle_call({:enrich, item}, from, state) do
  Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
    GenServer.reply(from, ExternalAPI.enrich(item))
  end)
  {:noreply, state}
end
```

### Don't do slow work in `init/1`

`init/1` blocks the supervisor starting the child (and everything after it in the tree). Defer to `handle_continue`:

```elixir
def init(opts) do
  {:ok, initial_state(opts), {:continue, :warm_cache}}
end

def handle_continue(:warm_cache, state) do
  {:noreply, %{state | cache: load_cache()}}
end
```

### Call timeouts

`GenServer.call/2` defaults to 5 seconds, then the **caller** exits. Calls on critical paths need an explicit timeout matched to the work, and callers must decide what a timeout means (retry? degrade?).

### Self-call deadlock

A GenServer that `GenServer.call`s itself (directly or through a module function) deadlocks — the message sits in its own mailbox while it waits. Same for two servers calling each other synchronously: circular calls deadlock under load. Break the cycle with `cast` + reply message, or restructure ownership.

---

## Message Safety

### Handle unexpected messages

A GenServer with no catch-all `handle_info/2` crashes on a stray message (e.g., a late `Task` result, a `:DOWN` after demonitor). Add a logging catch-all:

```elixir
def handle_info(msg, state) do
  Logger.warning("unexpected message: #{inspect(msg)}")
  {:noreply, state}
end
```

### `send/2` to a dead process silently drops

There is no error. If delivery matters, monitor the target or use a call.

### Mailbox growth is unbounded

`cast` has no backpressure — a fast producer floods a slow consumer's mailbox until the VM dies. If producers can outpace the consumer, use `call` (synchronous backpressure) or a real pipeline (GenStage, Broadway).

---

## Shared State

### ETS check-then-act is a race

Reads and writes are atomic individually; sequences are not. Two processes can both pass the "not exists" check.

```elixir
# Bad: TOCTOU — both processes insert
case :ets.lookup(table, key) do
  [] -> :ets.insert(table, {key, compute(key)})
  _ -> :ok
end

# Good: atomic insert-if-absent
:ets.insert_new(table, {key, compute(key)})
```

Atomic primitives: `:ets.insert_new/2`, `:ets.update_counter/3`, `:ets.select_replace/2`. Anything beyond them needs a single writer process serializing writes.

### Agent read-then-update is a race

```elixir
# Bad: value can change between get and update
value = Agent.get(agent, & &1)
Agent.update(agent, fn _ -> value + 1 end)

# Good: atomic read-modify-write
Agent.get_and_update(agent, fn v -> {v, v + 1} end)
```

### GenServer state is safe by construction

All mutations run through one mailbox — that serialization is the point. Don't bypass it by stashing the same data in ETS without an ownership story.

### Process dictionary

Avoid `Process.put/get` for logic — invisible state that breaks when work moves between processes (e.g., into a Task).

---

## Common Footguns

### Registry/name registration races

`Process.whereis` + conditional start is check-then-act. Use `{:via, Registry, ...}` names or handle `{:error, {:already_started, pid}}` from `start_link`.

### `Task.await` exits on timeout

`Task.await/2` (default 5s) exits the caller on timeout and the task keeps running. Use `Task.yield/2` + `Task.shutdown/2` when timeout is an expected outcome.

### `Task.async_stream` defaults

Concurrency defaults to scheduler count and `timeout: 5_000` **kills the whole stream** on one slow item. Set `max_concurrency` deliberately and `on_timeout: :kill_task` when partial results are acceptable.

### `async: true` tests with global state

Named processes, named ETS tables, `Application.put_env`, and the filesystem are shared across async tests — races manifest as flaky CI. Either inject per-test state or mark the file `async: false`.

---

## Idempotency

Queue and pipeline consumers (Oban, Broadway, SQS handlers) run with **at-least-once** delivery — retries and re-deliveries are normal operation.

- Handlers must be idempotent: replaying the same message must not double-apply side effects
- Guard external effects with idempotency keys, upserts (`on_conflict`), or unique constraints
- Oban: use `unique` options to suppress duplicate jobs; remember uniqueness windows are not transactional guarantees for the side effect itself
- A handler that reads state, decides, then writes must tolerate the world changing between retry attempts

---

## Review Checklist

When reviewing Elixir code for concurrency issues, check:

- [ ] No bare `spawn` for work that matters — supervised Tasks or tree children
- [ ] `Task.async` results always awaited; fire-and-forget uses `async_nolink`/`start_child`
- [ ] No slow I/O inside `handle_call`/`init` (use Task + `GenServer.reply`, or `handle_continue`)
- [ ] `GenServer.call` timeouts explicit on critical paths; callers handle timeout exits
- [ ] No self-calls or circular synchronous calls between servers
- [ ] Catch-all `handle_info/2` present on servers receiving external messages
- [ ] No unbounded `cast` flooding from producers that can outpace the consumer
- [ ] ETS sequences use atomic ops (`insert_new`, `update_counter`) or a single writer
- [ ] Agent updates use `get_and_update`, not get-then-update
- [ ] No `Process.put/get` carrying logic state
- [ ] `Task.async_stream` has deliberate `max_concurrency` and timeout handling
- [ ] Message/job handlers idempotent under at-least-once delivery
- [ ] Async tests don't touch named processes, named ETS tables, or Application env
