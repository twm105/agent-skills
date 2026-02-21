---
name: security-audit
description: >
  Structured repository security analysis combining a CLI scanner with
  agent-driven code review. Three profiles (quick/standard/deep), auto-detects
  languages, stores reports outside the repo tree. Use when asked to audit,
  scan, or review a repository for security issues, or when designing new
  features that need security consideration.
---

# security-audit

## Quick Reference

```
security-audit [scan] [-p quick|standard|deep] [--stdout] [--json] [--sarif]
security-audit setup [--check-only]
security-audit report [--latest|--list] [--stdout]
security-audit version
```

| Flag | Purpose |
|------|---------|
| `-p, --profile` | `quick` (secrets+deps), `standard` (default, +SAST/IaC), `deep` (+full history) |
| `-t, --tool <name>` | Run only specific tool(s), repeatable (accepts internal or common names, e.g. `semgrep`) |
| `--stdout` | Print full markdown report to terminal |
| `--json` | Print unified findings JSON to terminal |
| `--sarif` | Print SARIF 2.1.0 to stdout (for GitHub Security tab; excludes Low findings) |
| `--no-parallel` | Run tools sequentially instead of in parallel |
| `-v, --verbose` | Show tool commands and raw output |
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

## Design Review Workflow

Use this workflow when reviewing an architecture proposal, designing a new
feature, or when the user asks about security considerations before writing
code.

### 1. Identify Security-Relevant Scope

Determine whether the design touches security-sensitive areas:
- Authentication or authorization changes
- New API endpoints or trust boundaries
- Handling of PII, credentials, or sensitive data
- New dependencies or third-party integrations
- Infrastructure changes (ports, network, containers)
- AI agent permissions or tool configurations

If none apply, a design review is not needed — proceed normally.

### 2. Apply Design Principles

Read `references/secure-design.md` §Core Principles. For each of the 8
principles, check whether the proposed design respects or violates it.
Flag any gaps.

### 3. Threat Model (if warranted)

If the design introduces new trust boundaries or data flows, run the
lightweight threat model from `references/secure-design.md` §Lightweight Threat Modeling:
1. Identify assets, actors, and trust boundaries
2. Enumerate threats using STRIDE-lite
3. Map threats to principles and architecture patterns
4. Produce a threat-mitigation table

### 4. Present Design Recommendations

Deliver findings to the user:
- Which principles apply and whether the design satisfies them
- Relevant checklists from `references/secure-design.md` §Architecture-Level Security Patterns
- Threat-mitigation table (if threat modeling was performed)
- Specific, actionable recommendations — not generic advice

### 5. Post-Implementation Audit

After the feature is implemented, run the standard audit workflow (§Workflow
above) to verify that the design recommendations were correctly applied in
code.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Clean — no findings at Medium or above |
| 1 | Findings — at least one Medium+ finding |
| 2 | Tool error — one or more tools failed/timed out |

Priority: exit code 2 (tool error) takes precedence over exit code 1 (findings).
If a scan has both tool errors and findings, exit code 2 is returned to signal
incomplete results.

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
- `references/secure-design.md` — secure-by-design principles, architecture patterns, threat modeling
- `references/ci-integration.md` — CI/CD pipeline setup guide
- `assets/github-action.example.yml` — GitHub Actions workflow example
