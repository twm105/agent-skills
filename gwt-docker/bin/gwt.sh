# gwt.sh — Git worktree helper with Docker port isolation
# Source from .zshrc: source /path/to/agent-skills/gwt-docker/bin/gwt.sh

__GWT_PORT_BASE=40000
__GWT_PORT_CEILING=65535

# Branch name → Docker-safe name (/ → -, lowercase, truncate 50 chars)
__gwt_sanitize_name() {
  local name="$1"
  name="${name//\//-}"
  name="${name//_/-}"
  name="${(L)name}"
  # Remove leading/trailing hyphens
  name="${name#-}"
  name="${name%-}"
  # Truncate to 50 chars
  echo "${name:0:50}"
}

# Parse .env.template, extract *_PORT variable names in order
# Outputs variable names one per line; returns count via line count
__gwt_discover_ports() {
  local template="$1"
  if [[ ! -f "$template" ]]; then
    return 1
  fi
  # Match ${SOMETHING_PORT} patterns, extract var name
  grep -oE '\$\{[A-Z_]*_PORT\}' "$template" | sed 's/\${\(.*\)}/\1/' | awk '!seen[$0]++'
}

# Scan all worktrees' .gwt_index files, find first contiguous gap >= needed_size
# Args: repo_root needed_size
# Outputs: start_port
__gwt_find_port_range() {
  local repo_root="$1"
  local needed_size="$2"

  # Collect existing allocations
  local tmpfile
  tmpfile=$(mktemp)

  local wt_lines
  wt_lines=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null | grep '^worktree ' | sed 's/^worktree //')

  local wt_path
  while IFS= read -r wt_path; do
    [[ -z "$wt_path" ]] && continue
    if [[ -f "${wt_path}/.gwt_index" ]]; then
      cat "${wt_path}/.gwt_index" >> "$tmpfile"
    fi
  done <<< "$wt_lines"

  # Sort by start_port
  local sorted
  sorted=$(sort -n "$tmpfile" 2>/dev/null)
  rm -f "$tmpfile"

  local cursor=$__GWT_PORT_BASE

  if [[ -z "$sorted" ]]; then
    if (( cursor + needed_size > __GWT_PORT_CEILING )); then
      echo "error: not enough ports available" >&2
      return 1
    fi
    echo "$cursor"
    return 0
  fi

  # Walk sorted allocations to find first gap
  local found=""
  while read -r start size; do
    [[ -z "$start" || -z "$size" ]] && continue
    if (( cursor + needed_size <= start )); then
      found="$cursor"
      break
    fi
    cursor=$(( start + size ))
  done <<< "$sorted"

  if [[ -n "$found" ]]; then
    echo "$found"
    return 0
  fi

  # Try after last allocation
  if (( cursor + needed_size > __GWT_PORT_CEILING )); then
    echo "error: not enough ports available" >&2
    return 1
  fi
  echo "$cursor"
  return 0
}

# Given start_port + port var names, compute port values
# Args: start_port port_name1 port_name2 ...
# Outputs: VAR=value lines
__gwt_calculate_ports() {
  local start_port="$1"
  shift
  local offset=0
  local var
  for var in "$@"; do
    echo "${var}=$(( start_port + offset ))"
    offset=$(( offset + 1 ))
  done
}

# Check if a single port is in use (returns 0 if in use, 1 if free)
__gwt_check_port() {
  local port="$1"
  lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1
}

# Generate .env from .env.template using envsubst with explicit var list
# Args: template_path output_path worktree_name compose_project start_port port_var1 ...
__gwt_generate_env() {
  local template_path="$1"
  local output_path="$2"
  local worktree_name="$3"
  local compose_project="$4"
  local start_port="$5"
  shift 5
  local port_vars=("$@")

  # Build environment and var list for envsubst
  local env_vars=()
  env_vars+=("WORKTREE_NAME=${worktree_name}")
  env_vars+=("COMPOSE_PROJECT_NAME=${compose_project}")

  local var_list='${WORKTREE_NAME} ${COMPOSE_PROJECT_NAME}'
  local offset=0
  local var
  for var in "${port_vars[@]}"; do
    env_vars+=("${var}=$(( start_port + offset ))")
    var_list+=" \${${var}}"
    offset=$(( offset + 1 ))
  done

  # Run envsubst with explicit var list
  env "${env_vars[@]}" /opt/homebrew/bin/envsubst "$var_list" < "$template_path" > "$output_path"
}

# Pretty-print allocated port table for current worktree
__gwt_print_ports() {
  local gwt_index="$1"
  local template="$2"

  if [[ ! -f "$gwt_index" ]]; then
    echo "No port allocation found (.gwt_index missing)"
    return 1
  fi

  local start_port block_size
  read -r start_port block_size < "$gwt_index"

  echo "Port allocations (range: ${start_port}-$(( start_port + block_size - 1 ))):"
  echo "---"

  if [[ -f "$template" ]]; then
    local port_vars
    port_vars=($(__gwt_discover_ports "$template"))
    local offset=0
    local var
    for var in "${port_vars[@]}"; do
      printf "  %-30s %d\n" "$var" "$(( start_port + offset ))"
      offset=$(( offset + 1 ))
    done
  else
    echo "  (.env.template not found — showing raw range only)"
    echo "  start_port:  $start_port"
    echo "  block_size:  $block_size"
  fi
}

# Resolve the main worktree path for a given repo
__gwt_main_worktree() {
  local repo_root="$1"
  git -C "$repo_root" worktree list --porcelain 2>/dev/null | grep '^worktree ' | head -1 | sed 's/^worktree //'
}

# ─── Main Commands ───────────────────────────────────────────────────────────

gwt() {
  local start_claude=false
  local branch=""

  for arg in "$@"; do
    case "$arg" in
      --claude|-c) start_claude=true ;;
      *) branch="$arg" ;;
    esac
  done

  if [[ -z "$branch" ]]; then
    echo "Usage: gwt <branch-name> [--claude|-c]"
    return 1
  fi

  # Validate git repo
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "error: not inside a git repository"
    return 1
  fi

  local repo_name
  repo_name=$(basename "$repo_root")
  local worktree_path="${repo_root}/../${repo_name}-${branch}"
  local template="${repo_root}/.env.template"

  # ── Docker port allocation (if .env.template exists) ──
  local has_template=false
  local -a port_vars=()
  local needed_size=0
  local start_port=0
  local sanitized_name=""
  local compose_project=""

  if [[ -f "$template" ]]; then
    has_template=true
    sanitized_name=$(__gwt_sanitize_name "$branch")
    compose_project="${repo_name}-${sanitized_name}"

    # Discover port variables
    port_vars=($(__gwt_discover_ports "$template"))
    needed_size=${#port_vars[@]}

    if (( needed_size > 0 )); then
      # Find available port range
      start_port=$(__gwt_find_port_range "$repo_root" "$needed_size")
      if [[ $? -ne 0 ]]; then
        echo "error: could not allocate port range"
        return 1
      fi

      # Check port availability (warn only)
      local i
      for (( i = 0; i < needed_size; i++ )); do
        local port=$(( start_port + i ))
        if __gwt_check_port "$port"; then
          echo "warning: port $port (${port_vars[$((i+1))]}) is currently in use"
        fi
      done
    fi
  fi

  # ── Create worktree ──
  if ! git worktree add -b "$branch" "$worktree_path" 2>/dev/null; then
    # Branch may already exist — try without -b
    if ! git worktree add "$worktree_path" "$branch" 2>/dev/null; then
      echo "error: failed to create worktree for '$branch'"
      return 1
    fi
  fi

  cd "$worktree_path" || return 1

  # ── Docker port setup (if template existed) ──
  if [[ "$has_template" = true ]] && (( needed_size > 0 )); then
    # Write .gwt_index
    echo "${start_port} ${needed_size}" > .gwt_index

    # Generate .env
    __gwt_generate_env "$template" ".env" "$sanitized_name" "$compose_project" "$start_port" "${port_vars[@]}"

    echo ""
    __gwt_print_ports ".gwt_index" "$template"
    echo ""
  elif [[ "$has_template" = true ]]; then
    # Template exists but no port vars — still generate .env for WORKTREE_NAME/COMPOSE_PROJECT_NAME
    echo "0 0" > .gwt_index
    __gwt_generate_env "$template" ".env" "$sanitized_name" "$compose_project" "0"
  fi

  echo "Worktree ready: $worktree_path"

  # ── Launch Claude if requested ──
  if [[ "$start_claude" = true ]]; then
    claude
  fi
}

# Show port assignments for current worktree
gwt-ports() {
  local gwt_index=".gwt_index"
  if [[ ! -f "$gwt_index" ]]; then
    # Try to find it relative to git root
    local wt_root
    wt_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$wt_root" && -f "${wt_root}/.gwt_index" ]]; then
      gwt_index="${wt_root}/.gwt_index"
    else
      echo "No .gwt_index found — not a gwt-managed worktree, or no ports allocated."
      return 1
    fi
  fi

  # Find the original repo's .env.template
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  local main_wt
  main_wt=$(__gwt_main_worktree "$repo_root")
  local template="${main_wt}/.env.template"

  __gwt_print_ports "$gwt_index" "$template"
}

# List all worktrees with branch, path, and port range
gwt-list() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "error: not inside a git repository"
    return 1
  fi

  local repo_name
  repo_name=$(basename "$repo_root")
  local main_wt
  main_wt=$(__gwt_main_worktree "$repo_root")

  echo "Worktrees for ${repo_name}:"
  echo ""
  printf "  %-20s %-44s %s\n" "Branch" "Path" "Ports"
  printf "  %-20s %-44s %s\n" "──────" "────" "─────"

  local porcelain
  porcelain=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null)

  local wt_path="" wt_branch=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree\ (.+) ]]; then
      wt_path="${match[1]}"
    elif [[ "$line" =~ ^branch\ refs/heads/(.+) ]]; then
      wt_branch="${match[1]}"
    elif [[ "$line" =~ ^HEAD\ [0-9a-f] ]]; then
      # detached HEAD — skip branch assignment
      :
    elif [[ -z "$line" && -n "$wt_path" ]]; then
      # End of a worktree block — print it
      local port_info="—"
      if [[ "$wt_path" = "$main_wt" ]]; then
        port_info="(manual .env)"
      elif [[ -f "${wt_path}/.gwt_index" ]]; then
        local sp bs
        read -r sp bs < "${wt_path}/.gwt_index"
        if (( bs > 0 )); then
          port_info="${sp}–$(( sp + bs - 1 ))"
        else
          port_info="(no ports)"
        fi
      fi

      local display_branch="${wt_branch:-"(detached)"}"
      printf "  %-20s %-44s %s\n" "$display_branch" "$wt_path" "$port_info"

      wt_path=""
      wt_branch=""
    fi
  done <<< "$porcelain"

  # Handle last entry (porcelain output may not end with blank line)
  if [[ -n "$wt_path" ]]; then
    local port_info="—"
    if [[ "$wt_path" = "$main_wt" ]]; then
      port_info="(manual .env)"
    elif [[ -f "${wt_path}/.gwt_index" ]]; then
      local sp bs
      read -r sp bs < "${wt_path}/.gwt_index"
      if (( bs > 0 )); then
        port_info="${sp}–$(( sp + bs - 1 ))"
      else
        port_info="(no ports)"
      fi
    fi

    local display_branch="${wt_branch:-"(detached)"}"
    printf "  %-20s %-44s %s\n" "$display_branch" "$wt_path" "$port_info"
  fi
}

# Remove a worktree with Docker cleanup
gwt-cleanup() {
  local branch=""
  local force=false

  for arg in "$@"; do
    case "$arg" in
      --force|-f) force=true ;;
      *) branch="$arg" ;;
    esac
  done

  if [[ -z "$branch" ]]; then
    echo "Usage: gwt-cleanup <branch> [--force|-f]"
    return 1
  fi

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "error: not inside a git repository"
    return 1
  fi

  # Resolve worktree path from branch name
  local wt_path=""
  local porcelain
  porcelain=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null)

  local cur_path="" cur_branch=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree\ (.+) ]]; then
      cur_path="${match[1]}"
    elif [[ "$line" =~ ^branch\ refs/heads/(.+) ]]; then
      cur_branch="${match[1]}"
    elif [[ -z "$line" && -n "$cur_path" ]]; then
      if [[ "$cur_branch" = "$branch" ]]; then
        wt_path="$cur_path"
      fi
      cur_path=""
      cur_branch=""
    fi
  done <<< "$porcelain"

  # Handle last entry
  if [[ -n "$cur_path" && "$cur_branch" = "$branch" ]]; then
    wt_path="$cur_path"
  fi

  if [[ -z "$wt_path" ]]; then
    echo "error: no worktree found for branch '$branch'"
    return 1
  fi

  # Refuse to remove the main worktree
  local main_wt
  main_wt=$(__gwt_main_worktree "$repo_root")
  if [[ "$wt_path" = "$main_wt" ]]; then
    echo "error: refusing to remove the main worktree"
    return 1
  fi

  # Refuse if we're currently inside the target worktree
  local current_wt
  current_wt=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ "$current_wt" = "$wt_path" ]]; then
    echo "error: you are inside this worktree — cd out first"
    return 1
  fi

  # Confirm unless --force
  if [[ "$force" = false ]]; then
    printf "Remove worktree '%s'? [y/N] " "$branch"
    local answer
    read -r answer
    if [[ "${(L)answer}" != "y" ]]; then
      echo "Cancelled."
      return 0
    fi
  fi

  # Docker cleanup if docker-compose.yml exists
  if [[ -f "${wt_path}/docker-compose.yml" || -f "${wt_path}/docker-compose.yaml" || -f "${wt_path}/compose.yml" || -f "${wt_path}/compose.yaml" ]]; then
    echo "Stopping Docker services in ${wt_path}..."
    (cd "$wt_path" && docker compose down -v 2>/dev/null)
  fi

  # Remove worktree
  echo "Removing worktree..."
  if [[ "$force" = true ]]; then
    git worktree remove --force "$wt_path"
  else
    git worktree remove "$wt_path"
  fi

  if [[ $? -ne 0 ]]; then
    echo "error: failed to remove worktree (try --force)"
    return 1
  fi

  # Delete branch
  echo "Deleting branch '$branch'..."
  if [[ "$force" = true ]]; then
    git branch -D "$branch" 2>/dev/null
  else
    git branch -d "$branch" 2>/dev/null
  fi

  if [[ $? -ne 0 ]]; then
    echo "warning: could not delete branch '$branch' (may not be fully merged — use --force)"
  fi

  echo "Done."
}
