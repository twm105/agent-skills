# docker-compose.yml Conventions

## Scope

These conventions cover **development** `docker-compose.yml` files only. Production compose files are separate and out of scope for gwt-docker.

## Port Mapping Pattern

**Rule: Never hardcode host ports. Always use `${VAR:-default}:internal` syntax.**

```yaml
ports:
  - "${DB_PORT:-5432}:5432"
```

- `${DB_PORT:-5432}` — read from `.env`; fall back to `5432` if unset
- `:5432` — internal container port (always fixed)

The `:-default` fallback is critical: it means the root worktree works with standard ports even without a `.env` file.

## Environment Loading

Docker Compose automatically loads `.env` from the project directory. This means `${DB_PORT}` in `docker-compose.yml` is resolved from `.env` without any explicit `env_file` directive.

Use `env_file` only when your **application** (inside the container) needs those variables:

```yaml
services:
  web:
    build: .
    env_file: .env          # App reads DB_PORT to connect to database
    ports:
      - "${WEB_PORT:-3000}:3000"
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16
    # No env_file needed — Compose resolves ${DB_PORT} from .env for port mapping
    # But Postgres needs POSTGRES_* vars at runtime:
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-myapp_dev}
      POSTGRES_USER: ${POSTGRES_USER:-dev}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-devpass}
    ports:
      - "${DB_PORT:-5432}:5432"
```

## Volume and Network Isolation

`COMPOSE_PROJECT_NAME` handles all resource isolation automatically. Docker Compose prefixes every resource (networks, volumes, containers) with the project name.

```yaml
# CORRECT — simple volume names, Compose auto-prefixes
volumes:
  db_data:
  redis_data:

# WRONG — don't manually prefix with worktree name
volumes:
  ${WORKTREE_NAME}_db_data:    # Unnecessary and error-prone
```

What you see in `docker volume ls`:
- Root worktree: `myapp_db_data`
- Feature worktree: `myapp-feature-auth_db_data`

## Multi-Service Example

```yaml
services:
  web:
    build: .
    ports:
      - "${WEB_PORT:-3000}:3000"
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

  db:
    image: postgres:16
    ports:
      - "${DB_PORT:-5432}:5432"
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-myapp_dev}
      POSTGRES_USER: ${POSTGRES_USER:-dev}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-devpass}
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-dev}"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  worker:
    build: .
    command: ["npm", "run", "worker"]
    env_file: .env
    # No host port mapping — workers don't expose ports
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

  mailhog:
    image: mailhog/mailhog
    ports:
      - "${MAILHOG_SMTP_PORT:-1025}:1025"
      - "${MAILHOG_UI_PORT:-8025}:8025"

volumes:
  db_data:
  redis_data:
```

## Health Checks

Always add health checks to infrastructure services so `depends_on` with `condition: service_healthy` works:

```yaml
# Postgres
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-dev}"]
  interval: 5s
  timeout: 5s
  retries: 5

# Redis
healthcheck:
  test: ["CMD", "redis-cli", "ping"]
  interval: 5s
  timeout: 5s
  retries: 5

# MySQL
healthcheck:
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
  interval: 5s
  timeout: 5s
  retries: 5
```

## Service Startup Ordering

Use `depends_on` with health check conditions to ensure infrastructure services are ready before application services start:

```yaml
services:
  web:
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
```

## Layered Compose Files

For projects with both dev and prod compose files:

- `docker-compose.yml` — dev configuration with `${VAR:-default}` port patterns
- `docker-compose.prod.yml` — production overrides (fixed ports, no defaults needed)

The gwt-docker conventions apply only to the dev compose file.
