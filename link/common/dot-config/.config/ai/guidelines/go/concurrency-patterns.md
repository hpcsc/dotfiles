# Go Concurrency Patterns

## Goroutine Lifecycle

### Always make goroutines cancellable

Every goroutine must have a termination path, typically via `context.Context`.

```go
// Bad: goroutine runs forever
go func() {
    for msg := range ch {
        process(msg)
    }
}()

// Good: goroutine respects cancellation
go func() {
    for {
        select {
        case <-ctx.Done():
            return
        case msg, ok := <-ch:
            if !ok {
                return
            }
            process(msg)
        }
    }
}()
```

### Propagate the parent context

Never use `context.Background()` when a parent context exists. The parent's cancellation must propagate to child work.

```go
// Bad: orphaned context ignores shutdown
go func() {
    doWork(context.Background(), item)
}()

// Good: child inherits parent deadline/cancellation
go func() {
    doWork(ctx, item)
}()
```

### Use `errgroup` for structured concurrency

Prefer `errgroup.Group` over manual `sync.WaitGroup` + error collection.

```go
g, ctx := errgroup.WithContext(ctx)
for _, item := range items {
    g.Go(func() error {
        return process(ctx, item)
    })
}
if err := g.Wait(); err != nil {
    return err
}
```

---

## Channel Discipline

### Never send on a closed channel

A send on a closed channel panics. The sender owns closing; receivers never close.

### Use `select` with `ctx.Done()` for blocking operations

```go
select {
case result := <-ch:
    handle(result)
case <-ctx.Done():
    return ctx.Err()
}
```

### Prefer unbuffered channels unless you have a specific reason

Unbuffered channels synchronize sender and receiver. Buffered channels add complexity — use them only when you need decoupling or batching.

---

## Shared State

### Maps are not safe for concurrent access

Concurrent map read+write causes a runtime panic (not just a data race). Protect with `sync.Mutex` or use `sync.Map`.

```go
// Bad: runtime panic under concurrent access
m := make(map[string]int)
go func() { m["a"] = 1 }()
go func() { _ = m["a"] }()

// Good: mutex-protected access
mu.Lock()
m["a"] = 1
mu.Unlock()
```

### Slice append is not safe for concurrent access

Concurrent appends silently corrupt data — no panic, no race detector warning in some cases.

### Never copy a sync.Mutex

A mutex must not be copied after first use. This commonly happens with value receivers on structs containing a mutex.

```go
// Bad: value receiver copies the mutex
func (s MyStruct) DoSomething() { // s is a copy, including the mutex
    s.mu.Lock()
    defer s.mu.Unlock()
}

// Good: pointer receiver
func (s *MyStruct) DoSomething() {
    s.mu.Lock()
    defer s.mu.Unlock()
}
```

### Use `sync.Once` for lazy initialization

```go
var (
    instance *Client
    once     sync.Once
)

func GetClient() *Client {
    once.Do(func() {
        instance = newClient()
    })
    return instance
}
```

---

## Common Footguns

### `defer` in loops

`defer` runs at function return, not at end of loop iteration. Locks held and resources opened inside a loop accumulate until the function exits.

```go
// Bad: all locks held until function returns
for _, item := range items {
    mu.Lock()
    defer mu.Unlock() // deferred until function exit
    process(item)
}

// Good: extract to a function or unlock explicitly
for _, item := range items {
    func() {
        mu.Lock()
        defer mu.Unlock()
        process(item)
    }()
}
```

### Check-then-act (TOCTOU)

Read-then-write without holding a lock across both is a race condition.

```go
// Bad: another goroutine can modify between check and act
if val, ok := cache[key]; !ok {
    cache[key] = compute(key)
}

// Good: lock covers both check and act
mu.Lock()
if _, ok := cache[key]; !ok {
    cache[key] = compute(key)
}
mu.Unlock()
```

### `t.Parallel()` in tests

Parallel subtests share the parent test's scope. Captured loop variables and shared fixtures cause races.

```go
// Bad: all subtests share the last value of tc
for _, tc := range tests {
    t.Run(tc.name, func(t *testing.T) {
        t.Parallel()
        assert.Equal(t, tc.expected, run(tc.input)) // tc is shared
    })
}

// Good: capture loop variable (Go 1.22+ fixes this, but be explicit for clarity)
for _, tc := range tests {
    tc := tc
    t.Run(tc.name, func(t *testing.T) {
        t.Parallel()
        assert.Equal(t, tc.expected, run(tc.input))
    })
}
```

### Multiple lock acquisition order

Always acquire locks in a consistent order to prevent deadlocks.

---

## Review Checklist

When reviewing Go code for concurrency issues, check:

- [ ] Every goroutine has a cancellation path (context or channel close)
- [ ] Parent context propagated, not `context.Background()`
- [ ] No sends on potentially closed channels
- [ ] Blocking channel ops wrapped in `select` with `ctx.Done()`
- [ ] Maps and slices not accessed concurrently without synchronization
- [ ] No value receivers on types containing `sync.Mutex`
- [ ] No `defer` inside loops for locks or resource cleanup
- [ ] `sync.Once` for lazy initialization, not double-checked locking
- [ ] `errgroup.WithContext` used (not bare `errgroup.Group`) when cancellation matters
- [ ] Parallel test subtests don't share mutable state
- [ ] Lock acquisition order is consistent across call sites
