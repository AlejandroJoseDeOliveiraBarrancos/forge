# AI_RULES.md — Repository Engineering & AI Guidelines (SSOT)

Single source of truth for humans and AI assistants writing or reviewing code in this repo.
Code review procedure and output format live in `REVIEW_RULES.md` (this file defines *what is correct*, that one defines *how to check it*).

**Precedence when rules conflict:** security & correctness > runtime safety > architecture > style.
**Guiding question for every change:** *"What actually happens in production when this runs twice, late, concurrently, with stale input, or in a different tenant/environment than the one I tested?"*

## 0. Mandatory Review Rules Reference
**All AI agents and humans MUST read and apply `REVIEW_RULES.md` when performing any code review or diff analysis.** The review rules define the posture, severity rubric, procedure (Pass 0-3), 11 review lenses (A–K), and mandatory finding format. They are not optional — they are the enforcement mechanism for the principles in this file.

---

## 1. Architectural Principles

- **Clean / Hexagonal Architecture:** domain logic is isolated from HTTP, UI, DB drivers and cloud SDKs. Domain services have zero framework dependencies.
- **Dependency flow:** dependencies point inward. Infrastructure implements domain ports; the domain never imports infrastructure.
- **No I/O in the domain:** no direct DB query, HTTP call, queue publish or secret read inside a use case or domain service. Go through a port.
- **Single composition root:** wiring (which strategy, which adapter, which tenant config) happens in one place, never scattered through `if env == ...` branches in business code.
- **One place decides authority:** for every piece of data (credentials, config, state) there is exactly one authoritative source. Fallbacks to other sources are explicit, named, and gated (see §4).
- **Complexity limits (enforced by linter in CI, not by reviewer taste):**
  - Cyclomatic complexity per function ≤ 10
  - Cognitive complexity per function ≤ 15
  - Function length ≤ 50 lines
  - Nesting ≤ 3 levels of `if/else`; no new nested loops without justification

## 2. Code Quality & Formatting

- **Immutability & null safety:** prefer immutable data; handle every null/undefined path explicitly. Raise domain exceptions, not raw runtime errors.
- **Typing:** strict typing is mandatory. No `any`, no loose casts, no untyped dicts crossing a module boundary.
- **Naming:** domain-centric names (ubiquitous language of the bounded context).
- **Input normalization at the edge:** environment flags, headers, enum-like strings are parsed once through a shared helper (`strip().lower()`, accepts `true/1/yes`), never compared with a raw `== "true"`.
- **Comments and docstrings are part of the behavior.** If a change alters when a function returns `True`, the docstring changes in the same commit, including any escape-hatch env var.
- **Delete dead intent carefully:** if you remove a comment that explained a security or design decision, replace it with the new rationale.

## 3. Runtime Safety (mandatory)

### 3.1 Idempotency, retries and concurrency
- Assume **at-least-once delivery** for every queue/task/webhook (Cloud Tasks, Pub/Sub, HTTP retries, user double-clicks).
- **Never check-then-act.** Claim first, act second: reserve the slot (`submission_pending`, unique key, atomic `findOneAndUpdate`) *before* calling any external system.
- Every create-style endpoint that can be retried needs a **natural dedupe key** with a **unique index**; on duplicate, return the existing resource, not a new one.
- A handler that finds work already running/done returns **2xx**, not 409/500, when the caller will retry on non-2xx.
- Know the retry policy of the real queue (max attempts, backoff) — local config and exported infra config often differ. Review against the production one.

### 3.2 External calls and partial failure
- Timeouts of downstream calls must be **shorter** than the caller's timeout; otherwise the caller retries while the first call is still running.
- Do not map "any error" to a terminal failure state if the external side effect may already have happened (invoice stamped, payment sent, claim submitted). Use an `unknown` / `needs_reconciliation` state.
- Before re-issuing a non-idempotent side effect (CFDI/invoice, payment, claim), **ask the downstream system whether it already exists**.
- Multi-step operations need a documented rollback or compensation path; swallowed exceptions are forbidden.

### 3.3 Messaging
- Classify errors: **retryable** → nack/5xx with backoff; **non-retryable** (malformed JSON, unknown status, schema violation) → ack + structured log + dead-letter.
- Every subscription has a dead-letter policy and a max delivery attempts.
- No long-lived background consumers (streaming pull, cron loops) inside a service that can **scale to zero** (Cloud Run, App Engine without `min_instances`). Use push subscriptions or `min_instances ≥ 1`.

### 3.4 Data, indexes and time
- Indexes/constraints are created in **migrations or at startup**, never lazily on the first write.
- Never cache a rejected promise/future; clear the cache on failure so the next call can retry.
- Unique indexes include the full scope: `(tenant, database, name)`, not just `name`, whenever more than one tenant/db/environment can exist.
- `updated_at` / `created_at` use the server clock (`new Date()` / `now()`); event time is stored in a separate field (`occurred_at`). Timestamps must be monotonic.

### 3.5 Migrations
- Migration runners must be **target-aware**: any hardcoded DB name, URL or project id that contradicts a `--target` flag is a bug.
- Guards validate against the **configured** value for the selected target (e.g. `db_targets.json`), and still catch the real danger: a stale `active_target` pointing at the wrong database.
- Migration history is keyed per `(name, db_name)` and stored in a collection under a **protected prefix** (`cfg_*`) so cleanup commands cannot delete it.
- Every migration is idempotent and tested against **every configured target**, not only local.

## 4. Trust Boundaries & Security

- **Authoritative source wins.** Request-provided values (credentials, ids, flags) never override the secret store / config store unless an **explicit per-tenant flag** allows it. A change that inverts this order is a HIGH finding by default.
- **Callbacks/webhooks are untrusted:** require a signature or per-resource token, and verify the resource is in the expected lifecycle state before acting. Never trust the body to decide a state transition.
- **Stale client data is a threat model:** a user-supplied outdated password can lock a real account at the portal. Think about downstream lockout, rate limits and billing.
- Validate and sanitize at every system boundary; no secrets in code, logs, error messages or fixtures.
- Required secrets/config keys (e.g. `config.jwt.secret`) must exist in **every** environment's config, including local fixtures. A new required key without updating local/dev config is a startup break.

## 5. Configuration, Tenants & Environments

- **Changing a default changes behavior for every tenant.** Gate new behavior behind a flag (`USE_SECRET_MANAGER=false`, per-tenant flag) so existing tenants keep the old path.
- Keep a **behavior matrix** in the PR description for any change touching config: `tenant × environment × flag → resulting path`.
- Escape-hatch env vars (`BYPASS_*`) are documented **at the function that reads them**, parsed with the shared boolean helper, and never enabled by default.
- Health checks must prove **semantic readiness**, not only that the process is up. A service that returns `200` while `/api/<resource>` returns `count: 0` and requests fail with `CONFIG_ERROR` is broken — fail fast at startup or expose it in readiness.
- Notes, READMEs and config comments may only reference files/paths that exist.

## 6. Naming Conventions Are Load-Bearing

- Prefixes (`cfg_`, `ent_`, `tlm_`, ...) drive operational tooling (cleanup, backup, export, permissions).
- **Before adding a collection/table/queue/topic/env var**, grep ops scripts (`cmd_pallete.sh`, `Makefile`, cleanup/backup jobs, IaC) for filters and globs that will match or miss it.
- Anything that must survive a "clean runtime data" operation lives under the protected prefix.

## 7. Observability & Errors

- Structured logs with a correlation id (claim id, operation id, message id) on every external call and every nack/ack decision.
- Domain exceptions carry a stable error code; no bare `except:` / empty `catch`.
- Failures that are retried must be distinguishable in logs from first attempts.

## 8. Testing Expectations

A PR touching these areas is incomplete without tests for:
- **Duplicate delivery / retry** of the same message or request
- **Concurrent** execution of the same operation
- **Malformed** input and unknown status values (must not poison the queue)
- **Each tenant / target / flag variant** touched, including `true`, `True`, `TRUE`
- **Failure after side effect** (downstream succeeded, we crashed before saving)
- **Migrations** on every configured target, including re-running them

## 9. Pull Request Hygiene

- Separate **pre-existing issues** from issues introduced by the diff; offer to split them into another PR instead of silently expanding scope.
- If a risk is accepted for urgency, write it in the PR under **"Accepted risks"** with owner and follow-up — never leave it implicit.
- Cross-repo coupling (e.g. `hub-be#3` requires a new config key) is listed in the PR description with the dependent repos/PRs.

## 10. Critical Blockers (AI review default)

Flag as **blocking** unless the author documents an accepted risk:
1. Architecture violations: I/O inside domain use cases/services.
2. Non-idempotent side effect reachable by retry/duplicate/concurrency.
3. Authentication/authorization gaps, inverted trust model, secrets exposure, unauthenticated callbacks that trigger actions.
4. A feature, flag or `--target` that is announced but unreachable because of a hardcoded value or guard elsewhere.
5. Operational interaction that destroys or hides data (cleanup filters, history collections, migrations re-applied from scratch).
6. Swallowed exceptions, missing rollback, poison-message loops.
7. Complexity spikes beyond the limits in §1.