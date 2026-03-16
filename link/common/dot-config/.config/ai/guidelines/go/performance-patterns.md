# Go Performance Patterns

## Allocations & GC Pressure

### Pre-allocate slices and maps when size is known

Every `append` beyond capacity triggers a reallocation and copy. Pre-allocating avoids this entirely.

```go
// Bad: repeated reallocations as slice grows
var results []Item
for _, raw := range inputs {
    results = append(results, parse(raw))
}

// Good: single allocation
results := make([]Item, 0, len(inputs))
for _, raw := range inputs {
    results = append(results, parse(raw))
}
```

Same for maps:

```go
// Bad: map grows and rehashes incrementally
m := make(map[string]int)

// Good: sized map avoids rehashing
m := make(map[string]int, len(keys))
```

### Prefer value types for small structs

Small structs (up to ~64 bytes) passed by value stay on the stack. Pointers force heap allocation and add GC scan work.

```go
// Bad: unnecessary pointer causes heap escape
type Point struct{ X, Y float64 }

func newPoint(x, y float64) *Point {
    return &Point{X: x, Y: y} // escapes to heap
}

// Good: value type stays on stack
func newPoint(x, y float64) Point {
    return Point{X: x, Y: y}
}
```

Use `go build -gcflags='-m'` to verify escape behavior when it matters.

### Use `strings.Builder` for string construction

String concatenation in loops allocates a new string each iteration.

```go
// Bad: O(n^2) allocations
var s string
for _, part := range parts {
    s += part + ","
}

// Good: single allocation with size hint
var b strings.Builder
b.Grow(estimatedSize)
for _, part := range parts {
    b.WriteString(part)
    b.WriteByte(',')
}
result := b.String()
```

### Use `strconv` over `fmt` in hot paths

`fmt.Sprintf` uses reflection and allocates. `strconv` functions are type-specific and allocation-free.

```go
// Bad: reflection + allocation
s := fmt.Sprintf("%d", n)

// Good: direct conversion, no allocation
s := strconv.Itoa(n)
```

### Use `sync.Pool` for high-throughput, short-lived buffers

Pool byte buffers, encoders, or other temporary objects that are allocated and discarded rapidly.

```go
var bufPool = sync.Pool{
    New: func() any {
        return new(bytes.Buffer)
    },
}

func process(data []byte) string {
    buf := bufPool.Get().(*bytes.Buffer)
    defer func() {
        buf.Reset()
        bufPool.Put(buf)
    }()
    // use buf...
    return buf.String()
}
```

Only use `sync.Pool` when profiling confirms allocation pressure. It adds complexity and the pool is drained on every GC cycle.

---

## I/O & Networking

### Always set HTTP client timeouts

The default `http.Client` has no timeout — a slow server blocks the goroutine indefinitely.

```go
// Bad: no timeout
resp, err := http.Get(url)

// Good: explicit timeout
client := &http.Client{Timeout: 10 * time.Second}
resp, err := client.Get(url)
```

### Reuse `http.Client` and `http.Transport`

These types pool connections internally. Creating new ones per request defeats connection reuse.

```go
// Bad: new client per request — no connection pooling
func fetch(url string) (*http.Response, error) {
    client := &http.Client{Timeout: 10 * time.Second}
    return client.Get(url)
}

// Good: shared client, reuses connections
var client = &http.Client{Timeout: 10 * time.Second}

func fetch(url string) (*http.Response, error) {
    return client.Get(url)
}
```

### Close HTTP response bodies

An unclosed body holds the TCP connection open, preventing reuse.

```go
resp, err := client.Get(url)
if err != nil {
    return err
}
defer resp.Body.Close()
```

### Use buffered I/O

Raw `os.File` reads/writes issue a syscall per operation. Buffered I/O batches them.

```go
// Bad: syscall per write
f, _ := os.Create("out.txt")
for _, line := range lines {
    f.WriteString(line)
}

// Good: buffered writes
f, _ := os.Create("out.txt")
w := bufio.NewWriter(f)
for _, line := range lines {
    w.WriteString(line)
}
w.Flush()
```

### Use `io.Copy` for large payloads

`io.ReadAll` loads the entire payload into memory. `io.Copy` streams with a fixed buffer.

```go
// Bad: entire body in memory
body, _ := io.ReadAll(resp.Body)
os.WriteFile("large.bin", body, 0644)

// Good: streams with constant memory
out, _ := os.Create("large.bin")
defer out.Close()
io.Copy(out, resp.Body)
```

---

## Data Structure Choices

### Slice vs. map for small collections

For small N (< ~50 elements), a linear scan over a slice is faster than a map lookup due to cache locality and no hashing overhead.

```go
// For small, known key sets — slice + linear scan wins
type entry struct {
    key   string
    value int
}

func lookup(entries []entry, key string) (int, bool) {
    for _, e := range entries {
        if e.key == key {
            return e.value, true
        }
    }
    return 0, false
}
```

---

## Profiling First

**Never optimize without profiling.** Go provides excellent built-in tooling:

```bash
# CPU profile
go test -bench=BenchmarkX -cpuprofile=cpu.out
go tool pprof cpu.out

# Memory profile (allocations)
go test -bench=BenchmarkX -memprofile=mem.out
go tool pprof -alloc_space mem.out

# Escape analysis
go build -gcflags='-m' ./...

# Execution trace (scheduler, GC, goroutines)
go test -bench=BenchmarkX -trace=trace.out
go tool trace trace.out
```

### Benchmark correctly

```go
func BenchmarkProcess(b *testing.B) {
    // Setup outside the loop
    input := generateInput()
    b.ResetTimer()

    for b.Loop() {
        sink = process(input) // assign to package var to prevent dead code elimination
    }
}

// Prevent compiler from eliminating benchmark work
var sink Result
```

---

## Review Checklist

When reviewing Go code for performance issues, check:

- [ ] Slices and maps pre-allocated when size is known or estimable
- [ ] No string concatenation with `+` or `fmt.Sprintf` in loops
- [ ] `sync.Pool` used only where profiling justifies it
- [ ] HTTP clients have timeouts and are reused (not created per request)
- [ ] Response bodies are closed
- [ ] Large payloads streamed with `io.Copy`, not loaded with `io.ReadAll`
- [ ] Benchmarks use `b.ResetTimer()` and prevent dead code elimination
- [ ] Claims of "performance improvement" backed by benchmark data
