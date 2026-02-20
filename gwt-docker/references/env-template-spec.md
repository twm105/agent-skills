# .env.template Specification

## Purpose

`.env.template` is the source of truth for environment variables in gwt-managed projects. It lives at the repository root and is committed to git. When `gwt.sh` creates a feature worktree, it processes this template through `envsubst` to generate a `.env` file with unique port assignments.

## Variable Types

### gwt-managed variables (use `${VAR}` syntax)

These are substituted by `gwt.sh` during worktree creation:

| Variable | Value | Description |
|---|---|---|
| `${WORKTREE_NAME}` | Sanitized branch name | `feature/auth` → `feature-auth` |
| `${COMPOSE_PROJECT_NAME}` | `<repo>-<sanitized-branch>` | Isolates Docker resources |
| `${*_PORT}` | `40000 + offset` | Any variable ending in `_PORT` |

### Static variables (use literal values)

Everything else should be a literal value — no `${}` wrapping:

```bash
# GOOD — literal values
POSTGRES_DB=myapp_dev
POSTGRES_USER=dev
POSTGRES_PASSWORD=devpass
NODE_ENV=development
LOG_LEVEL=debug

# BAD — don't wrap non-gwt variables in ${}
POSTGRES_DB=${POSTGRES_DB}
```

## Variable Naming Rules

### Port variables

- **Must end in `_PORT`** (case-sensitive, uppercase)
- **Must use `${VAR}` syntax** to be discovered and substituted
- Convention: `<SERVICE>_PORT` (e.g., `DB_PORT`, `WEB_PORT`, `REDIS_PORT`, `MAILHOG_SMTP_PORT`)

### Discovery mechanism

`gwt.sh` uses this regex to find port variables:
```
\$\{[A-Z_]*_PORT\}
```

This means:
- `${DB_PORT}` — discovered ✓
- `${MAILHOG_SMTP_PORT}` — discovered ✓
- `${db_port}` — NOT discovered (lowercase)
- `DB_PORT=5432` — NOT discovered (no `${}` wrapper)
- `$DB_PORT` — NOT discovered (no braces)

### Order matters

Port values are assigned by position in the template file:
- First `*_PORT` variable → `start_port + 0`
- Second `*_PORT` variable → `start_port + 1`
- Third `*_PORT` variable → `start_port + 2`

If the same variable appears multiple times, only the first occurrence counts for ordering (duplicates are deduplicated).

## envsubst Processing

`gwt.sh` calls `envsubst` with an **explicit variable list**, meaning:

1. Only gwt-managed variables (`WORKTREE_NAME`, `COMPOSE_PROJECT_NAME`, `*_PORT` vars) are substituted
2. Any other `${...}` patterns pass through unchanged
3. Shell variables like `${HOME}`, `${USER}`, `${PATH}` are NOT expanded
4. Literal `$` signs that aren't part of `${VAR}` syntax are preserved

## Template Examples

### Valid template

```bash
# Project isolation
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
WORKTREE_NAME=${WORKTREE_NAME}

# Ports (gwt-managed)
DB_PORT=${DB_PORT}
WEB_PORT=${WEB_PORT}
REDIS_PORT=${REDIS_PORT}

# Static config (not substituted)
POSTGRES_DB=myapp_dev
POSTGRES_USER=dev
POSTGRES_PASSWORD=devpass
NODE_ENV=development
```

### Generated .env (for worktree `feature-auth`, first allocation)

```bash
# Project isolation
COMPOSE_PROJECT_NAME=myapp-feature-auth
WORKTREE_NAME=feature-auth

# Ports (gwt-managed)
DB_PORT=40000
WEB_PORT=40001
REDIS_PORT=40002

# Static config (not substituted)
POSTGRES_DB=myapp_dev
POSTGRES_USER=dev
POSTGRES_PASSWORD=devpass
NODE_ENV=development
```

### Invalid patterns

```bash
# BAD: lowercase port var (won't be discovered)
db_port=${db_port}

# BAD: no braces (won't be discovered)
DB_PORT=$DB_PORT

# BAD: wrapping static config in ${} (will be empty since it's not in the var list)
# Actually safe due to explicit envsubst var list — but confusing. Don't do it.
POSTGRES_DB=${POSTGRES_DB}
```

## Adding New Services

When adding a service to your project:

1. Add the `*_PORT` variable to `.env.template`
2. Existing worktrees are unaffected (their `.env` and `.gwt_index` are already written)
3. New worktrees will get a larger port block that includes the new port
4. If an existing worktree needs the new port, manually add it to that worktree's `.env`

## Root Worktree

The root (main) worktree's `.env` is **manually maintained**. `gwt.sh` never overwrites it. This lets you use meaningful, memorable ports:

```bash
# Root .env (handcrafted)
COMPOSE_PROJECT_NAME=myapp
DB_PORT=5432
WEB_PORT=3000
REDIS_PORT=6379
```

The `:-default` syntax in `docker-compose.yml` means the root works even without any `.env` file.
