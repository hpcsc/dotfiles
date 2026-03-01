# Go Preferred Libraries

Default library choices for greenfield Go projects. Use these unless there's a clear reason to deviate.

## Testing

- **`github.com/stretchr/testify`** — Use `require`, not `assert`. Tests should fail immediately on unexpected results, not continue with corrupted state.

## Logging

- **`log/slog`** — Default choice for structured logging.
- **`github.com/rs/zerolog`** — Acceptable when zero-allocation logging is justified (high-throughput hot paths).

## Database

- **`github.com/jackc/pgx/v5`** — PostgreSQL driver. Use `pgx` directly, not through `database/sql`.

## CLI

- **`github.com/urfave/cli/v2`** — CLI framework for command-line applications.

## Configuration

- **`github.com/caarlos0/env/v11`** — Environment variable parsing into structs.
