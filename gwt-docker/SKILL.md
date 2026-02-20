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

`gwt.sh` creates git worktrees for parallel development with automatic Docker port isolation. Source it from `.zshrc`:

```bash
source /path/to/agent-skills/gwt-docker/bin/gwt.sh
```

When a project has `.env.template`, gwt parses `*_PORT` variables, allocates a unique contiguous port block per worktree (40000+), and generates `.env` via `envsubst`. Docker Compose reads `.env` at runtime.

## Commands

| Command | Description |
|---------|-------------|
| `gwt <branch> [--claude\|-c]` | Create worktree, allocate ports, optionally launch Claude |
| `gwt-ports` | Show port assignments for current worktree |
| `gwt-list` | Show all worktrees with branch, path, and port range |
| `gwt-cleanup <branch> [-f]` | Remove worktree: stops Docker, removes worktree, deletes branch |

## Conventions

### .env.template (committed to git)

- Port variables **must** end in `_PORT` and use `${VAR}` syntax
- **Always include** `COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}`
- Order matters — port offset follows template order
- Only `${WORKTREE_NAME}`, `${COMPOSE_PROJECT_NAME}`, and `${*_PORT}` are substituted
- Static config uses literal values (not `${VAR}` syntax)

### docker-compose.yml

- **Never hardcode host ports** — use `"${DB_PORT:-5432}:5432"` pattern
- `COMPOSE_PROJECT_NAME` auto-isolates networks and volumes — no name hacks needed
- Use `env_file: .env` only if services read those vars at container runtime

### .gitignore

Must include `.env` and `.gwt_index`. The `.env.template` is committed.

## Port Allocation

- Block size = number of `*_PORT` variables in `.env.template`
- First-fit in 40000–65535 range
- Each worktree stores `start_port block_size` in `.gwt_index`
- Formula: `PORT_N = start_port + offset`
- Root worktree keeps its manual `.env` with standard ports

## Reference Files

For detailed specs and copy-ready examples:

- `references/env-template-spec.md` — full `.env.template` format rules
- `references/docker-compose-spec.md` — `docker-compose.yml` conventions
- `assets/env-template.example` — copy-ready `.env.template`
- `assets/docker-compose.example.yml` — copy-ready `docker-compose.yml`
