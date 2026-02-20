# CI Integration Guide

How to run security-audit in CI/CD pipelines. Covers GitHub Actions, GitLab CI, and general CI principles.

## Quick Start — GitHub Actions

Copy `assets/github-action.example.yml` to `.github/workflows/security-audit.yml` in your repository.

## Approach

CI runs the **quick** profile by default:
- Secrets detection (gitleaks on PR commits)
- Dependency vulnerability scan (language-specific tools)
- Fast execution (< 2 minutes)
- Exit-code driven pass/fail

For scheduled scans (weekly), use the **standard** profile to include static analysis and agent patterns.

## Exit Codes

| Code | CI behavior |
|---|---|
| 0 | Pass — no findings |
| 1 | Fail — security findings detected |
| 2 | Warning — tool error (findings may be incomplete) |

## GitHub Actions

### Tool Installation

Install tools in CI using the CLI's setup subcommand:

```yaml
- name: Install security tools
  run: security-audit setup
```

Or check what's available without installing:

```yaml
- name: Check tool availability
  run: security-audit setup --check-only
```

Or install specific tools individually to minimize CI time:

```yaml
- name: Install gitleaks
  run: brew install gitleaks

  # pip-audit requires Python ≤3.13 and an active venv — use trivy for CI instead
- name: Install trivy
  run: |
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
```

### Running via CLI

The simplest CI integration — run the CLI and use its exit code:

```yaml
# Quick scan on PRs
- name: Security audit (quick)
  run: security-audit -p quick -q

# Standard scan on schedule, save JSON for processing
- name: Security audit (standard)
  run: security-audit -p standard --json > findings.json

# Upload findings as artifact
- name: Upload findings
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: security-findings
    path: findings.json
    retention-days: 30
```

### Running Individual Tools

For CI, you may prefer running tools directly rather than through the full CLI:

```yaml
# Secrets scan on PR commits
- name: Gitleaks
  run: |
    gitleaks detect --source . --no-banner \
      --log-opts="${{ github.event.pull_request.base.sha }}..${{ github.sha }}" \
      --report-format sarif --report-path gitleaks.sarif

# Python/general dependency audit (trivy covers Python deps via manifests)
- name: trivy
  run: trivy fs --format json --severity HIGH,CRITICAL --quiet . -o trivy-results.json || true

# Node dependency audit
- name: npm audit
  run: npm audit --json > npm-audit.json || true

# Static analysis (opengrep — LGPL 2.1 fork of semgrep, identical CLI)
- name: Opengrep
  run: opengrep scan --config=auto --json --quiet . > opengrep.json
```

### SARIF Upload

GitHub Security tab can display SARIF-formatted results:

```yaml
- name: Upload SARIF
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: gitleaks.sarif
```

### Caching

Speed up repeated runs by caching tool databases:

```yaml
- name: Cache trivy DB
  uses: actions/cache@v4
  with:
    path: ~/.cache/trivy
    key: trivy-db-${{ runner.os }}

- name: Cache opengrep rules
  uses: actions/cache@v4
  with:
    path: ~/.cache/semgrep
    key: opengrep-rules-${{ hashFiles('.semgrep.yml') }}
```

## GitLab CI

```yaml
security-audit:
  stage: test
  image: python:3.12
  before_script:
    - pip install bandit
    - curl -fsSL https://raw.githubusercontent.com/opengrep/opengrep/main/install.sh | bash
    - apt-get update && apt-get install -y shellcheck
    - curl -sSfL https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_linux_amd64 -o /usr/local/bin/gitleaks && chmod +x /usr/local/bin/gitleaks
    - curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
  script:
    - gitleaks detect --source . --no-banner --log-opts="$CI_MERGE_REQUEST_DIFF_BASE_SHA..$CI_COMMIT_SHA"
    - trivy fs --scanners vuln .
    - bandit -r . --severity-level medium
  allow_failure: false
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

## Best Practices

### PR Checks (on every PR)
- Run **quick** profile only
- Fail on Critical/High findings
- Allow Medium findings as warnings
- Scan only changed files when possible (gitleaks commit range)

### Scheduled Scans (weekly/nightly)
- Run **standard** or **deep** profile
- Generate full report as artifact
- Notify on new findings via Slack/email
- Track finding trends over time

### Branch Protection
- Require security-audit check to pass before merge
- Exception process for acknowledged/accepted risks
- Auto-fix where possible (`npm audit fix`, dependency PRs)

### Secrets in CI
- Never log tool output that might contain discovered secrets
- Use `--redact` flags where available
- Store reports as artifacts with appropriate retention/access controls

## Threshold Configuration

Customize pass/fail thresholds per environment:

```yaml
env:
  # Fail CI if any Critical or High findings
  FAIL_ON: "critical,high"
  # Or be more permissive in development:
  # FAIL_ON: "critical"
```

Using the CLI's JSON output for custom threshold logic:

```bash
security-audit -p quick --json > findings.json

CRITICAL=$(jq '[.[] | select(.severity == "Critical")] | length' findings.json)
HIGH=$(jq '[.[] | select(.severity == "High")] | length' findings.json)

if [[ "$CRITICAL" -gt 0 ]] || [[ "$HIGH" -gt 0 ]]; then
  echo "Security audit failed: $CRITICAL critical, $HIGH high findings"
  exit 1
fi
```
