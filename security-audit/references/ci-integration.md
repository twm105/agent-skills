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
| 0 | Pass — no findings at Medium or above |
| 1 | Fail — at least one Medium+ finding |
| 2 | Warning — tool error, findings may be incomplete (takes precedence over exit 1) |

## GitHub Actions

### Tool Installation

Install tools in CI using the CLI's setup subcommand. The CLI is **not globally installed** on CI runners — copy `bin/security-audit` from this skill into your repo (e.g. `.github/scripts/security-audit`) and reference it by path:

```yaml
- name: Install security tools
  run: .github/scripts/security-audit setup
```

Or check what's available without installing:

```yaml
- name: Check tool availability
  run: .github/scripts/security-audit setup --check-only
```

Or install specific tools individually to minimize CI time:

```yaml
# macOS runners:
- name: Install gitleaks
  run: brew install gitleaks

# Linux runners (ubuntu-latest):
- name: Install gitleaks
  run: |
    GITLEAKS_VERSION=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r .tag_name)
    curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION#v}_linux_x64.tar.gz" | tar xz -C /usr/local/bin gitleaks

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
  run: .github/scripts/security-audit -p quick -q

# Standard scan on schedule, save JSON for processing
- name: Security audit (standard)
  run: .github/scripts/security-audit -p standard --json > findings.json

# Upload findings as artifact
- name: Upload findings
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: security-findings
    path: findings.json
    retention-days: 30
```

### SARIF Output for GitHub Security Tab

The `--sarif` flag produces SARIF 2.1.0 output that uploads to GitHub's Security tab. Results are **only visible to people with write access** — even on public repos. This keeps vulnerability details private while the workflow just passes/fails publicly.

```yaml
permissions:
  contents: read
  security-events: write  # Required for SARIF upload

steps:
  - name: Security audit
    run: .github/scripts/security-audit -p quick -q --sarif > results.sarif
    continue-on-error: true

  - name: Upload SARIF
    if: always()
    uses: github/codeql-action/upload-sarif@v3
    with:
      sarif_file: results.sarif
      category: security-audit
```

The SARIF output converts all unified findings (from all tools) into a single SARIF file with:
- Severity mapping: Critical/High → `error`, Medium → `warning` (Low findings are excluded from SARIF output)
- File locations with line numbers where available
- Remediation guidance, CVE/CWE references, and package version info in messages

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

# Static analysis
- name: Semgrep
  run: semgrep scan --config=auto --json --quiet . > semgrep.json
```

### Caching

Speed up repeated runs by caching tool databases:

```yaml
- name: Cache trivy DB
  uses: actions/cache@v4
  with:
    path: ~/.cache/trivy
    key: trivy-db-${{ runner.os }}

- name: Cache semgrep rules
  uses: actions/cache@v4
  with:
    path: ~/.cache/semgrep
    key: semgrep-rules-${{ hashFiles('.semgrep.yml') }}
```

## GitLab CI

```yaml
security-audit:
  stage: test
  image: python:3.12
  before_script:
    - pip install bandit
    - pip install semgrep
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
.github/scripts/security-audit -p quick --json > findings.json

CRITICAL=$(jq '[.[] | select(.severity == "Critical")] | length' findings.json)
HIGH=$(jq '[.[] | select(.severity == "High")] | length' findings.json)

if [[ "$CRITICAL" -gt 0 ]] || [[ "$HIGH" -gt 0 ]]; then
  echo "Security audit failed: $CRITICAL critical, $HIGH high findings"
  exit 1
fi
```
