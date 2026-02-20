---
name: security-audit
description: >
  Structured repository security analysis combining a CLI scanner with
  agent-driven code review. Three profiles (quick/standard/deep), auto-detects
  languages, stores reports outside the repo tree. Use when asked to audit,
  scan, or review a repository for security issues.
---

# security-audit

## Quick Reference

```
security-audit [scan] [-p quick|standard|deep] [--stdout] [--json] [--sarif]
security-audit setup [--check-only]
security-audit report [--latest|--list] [--stdout]
```

| Flag | Purpose |
|------|---------|
| `-p, --profile` | `quick` (secrets+deps), `standard` (default, +SAST/IaC), `deep` (+full history) |
| `-t, --tool <name>` | Run only specific tool(s), repeatable |
| `--stdout` | Print full markdown report to terminal |
| `--json` | Print unified findings JSON to terminal |
| `--sarif` | Print SARIF 2.1.0 to stdout (for GitHub Security tab) |
| `-q, --quiet` | Suppress progress output, exit code only |

Reports are stored in `~/.local/share/security-audit/<repo>/` — never in the repo tree.

## Workflow

### 1. Run the CLI

```bash
# First time — install tools
security-audit setup

# Scan the repository
security-audit -p standard
```

The CLI auto-detects languages, runs applicable tools in parallel, normalizes
findings to a unified severity scale, deduplicates, and prints a summary.

### 2. Review the Report

Read the summary printed to terminal. For full details:

```bash
security-audit report --stdout    # print latest report
```

Or read `findings.json` directly for structured data:

```bash
security-audit report --latest    # shows file path
```

### 3. Agent Code Review

After the CLI scan, perform manual code review for patterns that tools miss.
Use `references/agent-checks.md` — it contains 18 patterns with grep hints,
vulnerable code examples, and remediation guidance.

| Profile | Patterns to check |
|---------|-------------------|
| quick | None (CLI only) |
| standard | 1–5 (traditional) + 13–15 (AI/agent) |
| deep | All 18 patterns |

### 4. Present Combined Findings

Combine CLI findings and agent review into a single summary for the user:
- Group by severity (Critical → Low)
- Highlight top actionable items with file:line references
- Note tools skipped and any limitations

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Clean — no findings at Medium or above |
| 1 | Findings — at least one Medium+ finding |
| 2 | Tool error — one or more tools failed/timed out |

## Severity Scale

| Level | Meaning |
|-------|---------|
| Critical | Actively exploitable: known CVE with exploit, exposed secrets, RCE |
| High | Likely exploitable: high-confidence injection, auth bypass |
| Medium | Potential issue: moderate confidence, limited impact |
| Low | Best practice: informational, style, minor hardening |

## CI / GitHub Actions

The `security-audit` CLI is **not installed globally** on CI runners. When setting up a GitHub Actions workflow or any CI security check, you **must** copy the latest version of `bin/security-audit` from this skill into the target repository (e.g. as `.github/scripts/security-audit`). The workflow should then run it from that path.

```yaml
- name: Security audit
  run: .github/scripts/security-audit -p quick -q --sarif > results.sarif
```

Use `assets/github-action.example.yml` as the starting template. See `references/ci-integration.md` for SARIF upload (private to repo writers), caching, and threshold configuration.

## Reference Files

- `references/tool-catalog.md` — per-tool invocation, parsing, severity mapping
- `references/agent-checks.md` — 18 code-review patterns with examples
- `references/ci-integration.md` — CI/CD pipeline setup guide
- `assets/github-action.example.yml` — GitHub Actions workflow example
