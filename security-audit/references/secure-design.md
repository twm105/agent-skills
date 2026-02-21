# Secure-by-Design Reference

Proactive security guidance for design-time decisions. Use this document when
designing new features, reviewing architecture proposals, or threat modeling
before code is written.

Three sections build on each other:
1. **Core Principles** — foundational rules that prevent vulnerability classes
2. **Architecture Patterns** — concrete checklists for common security domains
3. **Threat Modeling** — lightweight process to surface risks in a single pass

---

## Core Principles

Eight principles that prevent the majority of security defects when applied
during design. Each includes agent guidance for when and how to apply it.

### 1. Least Privilege

**Definition**: Grant the minimum permissions, access, and capabilities needed
for a component to perform its function — nothing more.

**Agent guidance**: Apply whenever a design introduces a new service account,
API key scope, file system access, database role, or tool permission. Ask:
"What is the maximum damage if this credential is compromised?" and scope
down until the answer is acceptable.

**Example**: A reporting service needs read access to the `orders` table. Grant
`SELECT` on `orders` only — not `SELECT` on the entire database, and never
`INSERT`/`UPDATE`/`DELETE`.

---

### 2. Defense in Depth

**Definition**: Layer multiple independent security controls so that failure of
any single layer does not compromise the system.

**Agent guidance**: Apply whenever a design relies on a single check for a
critical security property. For every trust boundary, identify at least two
independent controls. If the design has "if this one check passes, access is
granted," flag it.

**Example**: An API endpoint that modifies user data should enforce: (1) auth
token validation at the gateway, (2) permission check in the service layer,
(3) row-level ownership check at the database query. Compromising the gateway
alone should not grant write access.

---

### 3. Secure Defaults

**Definition**: The zero-configuration, out-of-the-box path must be the
restrictive path. Security should require opting out, not opting in.

**Agent guidance**: Apply when designing configuration, feature flags, or
framework defaults. Check: "What happens if a developer uses this component
without reading the docs?" If the answer involves an open permission, an
unencrypted channel, or a permissive policy — the default is insecure.

**Example**: A new API framework should require authentication on all endpoints
by default. Developers explicitly mark public endpoints with `@public`, rather
than marking protected endpoints with `@auth_required`.

---

### 4. Fail Closed

**Definition**: When an error, exception, or ambiguous condition occurs, the
system must deny access rather than allow it.

**Agent guidance**: Apply to every error path and edge case in auth, authz,
validation, and policy enforcement. Trace what happens when: a token is
malformed, a policy engine is unreachable, a database query times out, an
input doesn't match any rule. If any of these default to "allow," flag it.

**Example**: An authorization service that cannot reach the policy database
should return 403 Forbidden, not fall through to an unprotected path. A JWT
with an unrecognized algorithm should be rejected, not processed with a
default algorithm.

---

### 5. Minimize Attack Surface

**Definition**: Every endpoint, dependency, port, protocol, and feature
increases the attack surface. Each one needs explicit justification.

**Agent guidance**: Apply during architecture review and dependency selection.
For every new endpoint, ask: "Is this necessary for the feature?" For every
new dependency, ask: "Does the value justify the supply-chain risk?" Flag
admin interfaces exposed to the public internet, debug endpoints left enabled,
and unused dependencies.

**Example**: An internal admin API should be on a separate network interface
or behind a VPN — not exposed alongside the public API on the same port with
only an auth check separating them.

---

### 6. Separation of Privilege

**Definition**: Critical operations should require multiple independent
conditions, parties, or credentials — never a single point of authorization.

**Agent guidance**: Apply to destructive operations (data deletion, account
deactivation, production deployments, secret rotation). Check whether a single
compromised credential or a single actor can trigger the operation. If yes,
recommend requiring a second factor or approval flow.

**Example**: Deleting a user account should require: (1) the authenticated
user confirms via re-entering their password, (2) a confirmation delay or
email verification step. A single API call with a valid session token should
not be sufficient for irreversible actions.

---

### 7. Don't Trust Input

**Definition**: All data crossing a trust boundary is untrusted until validated.
Trust boundaries exist between: user and server, service and service, file
system and application, environment and code.

**Agent guidance**: This is the most broadly applicable principle. Apply at
every point where data enters a component from outside its trust boundary.
Identify all input channels: HTTP parameters, headers, file uploads, database
reads (if the database is shared), environment variables, message queue
payloads, LLM outputs. Each needs validation appropriate to its use.

**Example**: A service that reads messages from a queue shared with other teams
must validate and sanitize message payloads the same way it would validate
HTTP input — the queue is a trust boundary.

---

### 8. Economy of Mechanism

**Definition**: Security mechanisms should be simple enough to verify. Prefer
well-understood, auditable controls over clever or flexible ones.

**Agent guidance**: Apply when choosing between security implementations. Prefer
standard library functions over custom cryptography, established frameworks
over hand-rolled auth, and simple allowlists over complex pattern matching.
If a security-critical component cannot be explained in a short paragraph,
it is too complex.

**Example**: Use `bcrypt.hashpw()` for password hashing instead of building a
custom scheme with HMAC + salt + iterations. The custom scheme may be
technically correct, but bcrypt is battle-tested, widely reviewed, and has
clear failure modes.

---

## Architecture-Level Security Patterns

Concrete patterns for six domains. Each includes a design checklist — items the
agent should verify against any proposed architecture.

### Authentication

**Pattern**: Establish identity through verifiable credentials. Choose session-based
(stateful, server-side) or token-based (stateless, JWT/opaque) based on the
deployment model. Enforce token lifecycle: issuance, expiration, refresh, revocation.

**Design checklist**:
- [ ] Authentication mechanism chosen (session vs. token) with justification
- [ ] Token/session expiration configured (access token: short-lived, refresh token: bounded)
- [ ] Token storage defined (HttpOnly cookies for web, secure storage for mobile — never localStorage for sensitive tokens)
- [ ] Service-to-service auth specified (mTLS, API keys with rotation, or OAuth2 client credentials)
- [ ] MFA required or recommended for privileged accounts
- [ ] Brute-force protection in place (rate limiting, account lockout, progressive delays)
- [ ] Session invalidation on password change / privilege change

### Authorization

**Pattern**: Enforce who-can-do-what through a centralized policy layer. Choose
a model — RBAC (role-based), ABAC (attribute-based), or ReBAC (relationship-based)
— based on complexity of access rules. Centralize enforcement to prevent
scattered, inconsistent checks.

**Design checklist**:
- [ ] Authorization model selected (RBAC/ABAC/ReBAC) with justification
- [ ] Default policy is deny — access requires an explicit grant
- [ ] Policy enforcement centralized (middleware, gateway, or policy engine — not ad-hoc per handler)
- [ ] Resource-level permissions enforced (not just role checks, but ownership/relationship checks)
- [ ] Privilege escalation paths identified and gated (role changes require admin + confirmation)
- [ ] Authorization decisions logged for audit trail

### API Security

**Pattern**: Treat every API endpoint as a trust boundary. Authenticate by
default, validate all input at the boundary, and enforce resource limits to
prevent abuse.

**Design checklist**:
- [ ] All endpoints require authentication by default (public endpoints explicitly marked)
- [ ] Input validation at the API boundary (schema validation, type checking, size limits)
- [ ] Rate limiting configured per endpoint or per client
- [ ] Pagination enforced on list endpoints (no unbounded result sets)
- [ ] Request size limits configured (body, file upload, header size)
- [ ] Error responses do not leak internal details (stack traces, SQL errors, internal paths)
- [ ] API versioning strategy defined to support security patches without breaking clients

### Secrets Management

**Pattern**: Secrets (API keys, database credentials, encryption keys, tokens)
must never exist in source code, logs, or error messages. Design the system to
inject secrets at runtime from a trusted source.

**Design checklist**:
- [ ] Secret storage mechanism chosen (environment variables for simple deployments, secrets manager for production)
- [ ] Rotation strategy defined (zero-downtime rotation: support two active credentials during rollover)
- [ ] Secrets excluded from version control (`.env` in `.gitignore`, no hardcoded values)
- [ ] Logging confirmed to never include secrets (audit log formats, error serialization)
- [ ] Secret access scoped (each service gets only the secrets it needs)

### Data Protection

**Pattern**: Classify data by sensitivity (PII, sensitive, internal, public) and
apply protections proportional to classification. Encrypt at rest and in transit.
Log access to sensitive data.

**Design checklist**:
- [ ] Data classification applied (PII, financial, health, credentials, internal, public)
- [ ] Encryption at rest for sensitive data (database-level, field-level, or disk-level)
- [ ] Encryption in transit enforced (TLS 1.2+ for all connections, no plaintext fallback)
- [ ] Password hashing uses a modern algorithm (bcrypt, argon2, or scrypt — never MD5/SHA1)
- [ ] PII handling complies with applicable regulations (GDPR right-to-delete, data minimization)
- [ ] Audit logging for access to sensitive data (who accessed what, when)

### Dependency Security

**Pattern**: Every dependency is an extension of the attack surface. Minimize
the number of dependencies, pin versions, and verify integrity.

**Design checklist**:
- [ ] Dependencies justified (each one serves a clear purpose not easily replaced by standard library)
- [ ] Lock files committed and used for reproducible builds (`package-lock.json`, `poetry.lock`, `go.sum`)
- [ ] Automated vulnerability scanning configured (Dependabot, Snyk, `pip-audit`, `npm audit`)
- [ ] Update cadence defined (security patches: immediate, minor/major: scheduled review)
- [ ] Transitive dependencies reviewed for known high-risk packages
- [ ] Registry trust model considered (private registry or vendoring for high-security environments)

---

## Lightweight Threat Modeling

A four-step process the agent can execute in a single response turn. Based on
STRIDE, simplified for design-time review of a feature or component.

### When to threat model

Run this process when a design introduces any of:
- New trust boundaries (public endpoints, service-to-service calls, third-party integrations)
- New data stores or data flows for sensitive information
- New authentication or authorization mechanisms
- Changes to an existing security boundary

### Step 1: Identify Assets and Actors

Enumerate what you're protecting and who interacts with it.

**Assets** — classify by sensitivity:
| Classification | Examples |
|----------------|----------|
| Credentials | API keys, passwords, tokens, private keys |
| PII | Email, name, address, phone, payment info |
| Sensitive | Business logic, internal IDs, audit logs |
| Internal | Configuration, feature flags, metrics |
| Public | Marketing content, public API docs |

**Actors** — enumerate who interacts:
- Anonymous users (unauthenticated)
- Authenticated users (with roles/permissions)
- Internal services (microservices, background jobs)
- Administrators (elevated privileges)
- Third-party integrations (webhooks, OAuth providers)
- AI agents (Claude Code, MCP servers, automated tools)

**Trust boundaries** — draw lines between actors with different trust levels:
- Internet ↔ load balancer/CDN
- Load balancer ↔ application server
- Application ↔ database
- Service ↔ service (cross-team or cross-trust)
- User ↔ AI agent ↔ tools/filesystem

### Step 2: Enumerate Threats (STRIDE-lite)

For each trust boundary identified in Step 1, ask one question per STRIDE
category:

| Category | Question |
|----------|----------|
| **S**poofing | Can an actor fake their identity at this boundary? |
| **T**ampering | Can data be modified in transit or at rest across this boundary? |
| **R**epudiation | Can an action be performed without an audit trail at this boundary? |
| **I**nformation Disclosure | Can sensitive data leak across this boundary? |
| **D**enial of Service | Can this boundary be overwhelmed or made unavailable? |
| **E**levation of Privilege | Can a lower-privilege actor gain higher access at this boundary? |

Record each "yes" or "possibly" answer as a threat to address.

### Step 3: Map to Principles and Patterns

Connect each identified threat to:
1. The **core principle** (§Core Principles) that prevents it
2. The **architecture pattern** (§Architecture Patterns) that provides the concrete control

This step ensures mitigations are grounded in established patterns, not ad-hoc
fixes.

| Threat type | Primary principles | Key patterns |
|-------------|-------------------|--------------|
| Spoofing | Don't Trust Input, Defense in Depth | Authentication |
| Tampering | Don't Trust Input, Fail Closed | Data Protection, API Security |
| Repudiation | Economy of Mechanism | Data Protection (audit logging) |
| Information Disclosure | Least Privilege, Minimize Attack Surface | Secrets Management, Data Protection |
| Denial of Service | Minimize Attack Surface | API Security (rate limiting, pagination) |
| Elevation of Privilege | Least Privilege, Separation of Privilege | Authorization |

### Step 4: Document Mitigations

Produce a threat-mitigation table. This is the deliverable the agent presents
to the user.

**Template**:

| # | Threat | Boundary | STRIDE | Mitigation | Principle |
|---|--------|----------|--------|------------|-----------|
| 1 | _description_ | _which boundary_ | _S/T/R/I/D/E_ | _specific control_ | _principle name_ |
| 2 | ... | ... | ... | ... | ... |

**Example** (for a "new public API endpoint with user data"):

| # | Threat | Boundary | STRIDE | Mitigation | Principle |
|---|--------|----------|--------|------------|-----------|
| 1 | Unauthenticated access to user data | Internet ↔ API | S | JWT validation at gateway + service layer | Defense in Depth |
| 2 | SQL injection via query parameters | API ↔ Database | T | Parameterized queries, input schema validation | Don't Trust Input |
| 3 | No audit trail for data access | API ↔ Database | R | Structured audit log for all PII reads | Economy of Mechanism |
| 4 | PII leaked in error responses | Internet ↔ API | I | Sanitized error format, no stack traces | Minimize Attack Surface |
| 5 | API overwhelmed by bulk requests | Internet ↔ API | D | Per-client rate limiting, pagination required | Minimize Attack Surface |
| 6 | Regular user accesses admin endpoints | API ↔ Service | E | RBAC with deny-by-default, resource ownership checks | Least Privilege |

---

## Detection-to-Prevention Mapping

Cross-reference connecting the 18 agent review patterns in `agent-checks.md` to
the core principles that prevent each vulnerability class. Use this table to
move from reactive detection to proactive design.

| # | Pattern | Prevention Principles & Patterns |
|---|---------|----------------------------------|
| 1 | Hardcoded Secrets | Secrets Management, Secure Defaults |
| 2 | SQL Injection | Don't Trust Input, Defense in Depth |
| 3 | Command Injection | Don't Trust Input, Least Privilege |
| 4 | XSS | Don't Trust Input, Secure Defaults |
| 5 | Path Traversal | Don't Trust Input, Minimize Attack Surface |
| 6 | Insecure Deserialization | Don't Trust Input, Economy of Mechanism |
| 7 | Weak Cryptography | Economy of Mechanism, Secure Defaults |
| 8 | SSRF | Don't Trust Input, Minimize Attack Surface |
| 9 | Overly Permissive CORS | Secure Defaults, Minimize Attack Surface |
| 10 | Unsafe eval/exec | Don't Trust Input, Least Privilege |
| 11 | Insecure Random | Economy of Mechanism, Secure Defaults |
| 12 | Auth/Authz Weaknesses | Least Privilege, Fail Closed, Separation of Privilege |
| 13 | CLAUDE.md Injection | Don't Trust Input, Secure Defaults |
| 14 | MCP Permissions | Least Privilege, Minimize Attack Surface |
| 15 | .claude/ Directory | Secrets Management, Secure Defaults |
| 16 | Skill Injection | Don't Trust Input, Economy of Mechanism |
| 17 | Prompt Injection | Don't Trust Input, Defense in Depth |
| 18 | Tool Escalation | Least Privilege, Separation of Privilege |
