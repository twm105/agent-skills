---
name: gwt-docker
description: >
  Conventions for Docker port allocation in git worktree environments.
  Use when creating or modifying docker-compose.yml, .env.template, or
  .env files in projects that use git worktrees for parallel development.
  Ensures no port conflicts between parallel worktree instances.
---

# gwt-docker: Docker Port Isolation for Git Worktrees

## Overview

`gwt.sh` creates git worktrees for parallel development (`gwt feature-x --claude`). When projects use Docker, parallel worktrees clash on ports (e.g. two instances both want port 5432). This skill teaches the conventions that prevent port conflicts.

**How it works**: `gwt.sh` parses `.env.template` for `*_PORT` variables, allocates a unique contiguous port block per worktree (starting from 40000), and generates `.env` via `envsubst`. Docker Compose reads `.env` at runtime.

## Port Allocation

- **Fully dynamic** — block size = number of `*_PORT` variables in `.env.template`
- **First-fit** — new worktrees find the first available gap in the 40000-65535 range
- **Per-worktree tracking** — each worktree stores `start_port block_size` in `.gwt_index`
- **Root worktree is manual** — the main checkout keeps its handcrafted `.env` with meaningful ports (e.g., 5432 for Postgres). Only feature worktrees get auto-generated `.env` files.

Port assignment formula: `PORT_N = start_port + offset` (offset = position in `.env.template`)

## .env.template Rules

The `.env.template` file is the source of truth. It lives in the repo root and is committed to git.

### Required patterns

```bash
# Project isolation (REQUIRED)
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}

# Worktree identifier (available for use in configs)
WORKTREE_NAME=${WORKTREE_NAME}

# Port variables — MUST end in _PORT to be discovered by gwt.sh
DB_PORT=${DB_PORT}
WEB_PORT=${WEB_PORT}
REDIS_PORT=${REDIS_PORT}
```

### Rules

1. **Port variables must end in `_PORT`** — this is how `gwt.sh` discovers them
2. **Use `${VAR}` syntax** for gwt-managed variables only
3. **Use literal values** for static config (DB names, passwords, feature flags)
4. **Always include `COMPOSE_PROJECT_NAME`** — this isolates Docker networks and volumes
5. **Order matters** — port assignment follows template order (first `*_PORT` gets offset 0)

### What gets substituted

Only these variables are replaced by `envsubst`:
- `${WORKTREE_NAME}` — sanitized branch name
- `${COMPOSE_PROJECT_NAME}` — `<repo>-<sanitized-branch>`
- `${*_PORT}` — all discovered port variables

Everything else passes through literally. This means `${HOME}` or `${PATH}` in your template won't be touched.

## docker-compose.yml Rules (Dev Only)

This covers development compose files only. Production compose is out of scope.

### Port mapping pattern

**Never hardcode host ports.** Always use environment variable substitution with defaults:

```yaml
ports:
  - "${DB_PORT:-5432}:5432"
  - "${WEB_PORT:-3000}:3000"
  - "${REDIS_PORT:-6379}:6379"
```

The `:-default` syntax means the root worktree (with its manual `.env` or no `.env`) still works with standard ports.

### Environment loading

Compose auto-loads `.env` from the project directory. No explicit `env_file` needed for port variables. Use `env_file` only if your services need those values at container runtime:

```yaml
services:
  web:
    env_file: .env    # Only if the app reads these vars at runtime
    ports:
      - "${WEB_PORT:-3000}:3000"
```

### Volume and network isolation

**Do not add worktree-specific volume name hacks.** `COMPOSE_PROJECT_NAME` handles this automatically — Docker Compose prefixes all resources (networks, volumes) with the project name.

```yaml
# GOOD — Compose auto-prefixes with COMPOSE_PROJECT_NAME
volumes:
  db_data:

# BAD — Don't do this
volumes:
  ${WORKTREE_NAME}_db_data:
```

## .gitignore Rules

Your `.gitignore` must include:

```
.env
.gwt_index
```

The `.env.template` file should NOT be gitignored — it's committed to the repo.

## Reference Files

For detailed specifications and copy-ready examples, see:
- `references/env-template-spec.md` — full `.env.template` format rules
- `references/docker-compose-spec.md` — `docker-compose.yml` conventions
- `assets/env-template.example` — copy-ready `.env.template`
- `assets/docker-compose.example.yml` — copy-ready `docker-compose.yml`
