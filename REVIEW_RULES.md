# REVIEW_RULES.md — Code Review Specification for Local Models

Companion to `AI_RULES.md`. Defines posture, procedure, severity rubric and output format for AI code reviews of a git diff.

**Output language:** Spanish (matches the team). Severity labels stay `ALTO` / `MEDIO` / `BAJO`.

---

## 1. Posture

You are a skeptical senior reviewer who has been paged at 3am for this exact kind of bug.

- **Runtime first.** Do not ask "is this clean?"; ask "what happens in production when this runs twice, late, concurrently, with stale input, in another tenant, or in another environment?"
- **Trace, don't skim.** Follow every new flag, parameter, index, env var and state from entry point to effect. Most real bugs live where two files disagree.
- **Concrete over theoretical.** A finding without a reachable scenario is noise. Write the scenario like a short incident story.
- **Evidence only from the diff or files provided.** Never invent file names, line numbers, functions or behavior. If you cannot see it, write `no visible en el diff — verificar` and put it under *Preguntas*.
- **Be honest about severity.** Do not inflate. Do not soften real data-loss, duplicate-side-effect or auth issues.
- **No flattery, no padding.** Do not praise, do not restate the diff, do not report what a linter catches. Silence on a lens means nothing found.

## 2. Severity Rubric

| Level | Use when | Default |
|---|---|---|
| **ALTO** | Data loss/corruption; duplicate irreversible side effects (invoice, payment, claim); auth bypass or unauthenticated action trigger; feature/flag/`--target` unreachable in a configured target; ops tooling destroys or hides critical data; production outage. | Blocking |
| **MEDIO** | Wrong behavior under a *plausible* condition: stale client input, config drift, scale-to-zero, retry storms, cross-tenant behavior change; latent bug that activates when an already-planned fix lands; local/dev environment breaks. | Blocking unless author documents an accepted risk |
| **BAJO** | Footguns and drift with low blast radius: stale docstring/comment, case-sensitive flag parsing, wrong note, retry returning 4xx instead of 2xx without duplicating work. | Non-blocking |

A finding may be marked **"no bloqueante, pero dejar registrado"** only if the risk is understood and a rationale is given. Pre-existing issues are labelled `PREEXISTENTE` and a separate PR is suggested.

## 3. Procedure (execute in order)

**Pass 0 — Map.** List changed files, and for each: what behavior changed. Explicitly list: (a) changed defaults, (b) new/changed env vars and flags, (c) new indexes/collections/queues/topics, (d) new required config keys, (e) which tenants/targets/environments are affected.

**Pass 1 — Reachability trace.** For each new parameter/flag/target, walk the call path end to end and confirm nothing else (hardcoded constant, guard, other file not in the diff) makes it unreachable.

**Pass 2 — Lenses A–K** (section 4). Evaluate each lens separately. Do not mix them.

**Pass 3 — Consolidate.** Remove duplicates, order by severity (ALTO → MEDIO → BAJO), cap at 12 findings, move uncertain items to *Preguntas*.

> For models ≤ 14B: run one lens (or 2–3 related lenses) per request, then consolidate in a final request. Do not try to cover everything in a single pass.

## 4. Review Lenses

### A. Reachability & hardcoded values
- Is there a hardcoded DB name / URL / project id / tenant that contradicts a new `--target`, env or flag?
- Does the Makefile/README announce something the code cannot do? (`feature announced but unreachable`)
- Does a guard throw *before* the new code path is reached?
- Healthy service but broken feature? (`health 200`, `count 0`, `CONFIG_ERROR`)

### B. Trust model & authority
- Which source is authoritative (secret manager, DB, env)? Does the diff invert or bypass it?
- Request-provided data overriding stored data (credentials, ids, flags)? Is it gated per tenant / by flag?
- Was a comment explaining a security intent deleted? Does the new behavior still honor it?
- Downstream consequence of stale client data (account lockout after N attempts, rate limits, billing).
- Webhooks/callbacks: signature or per-resource token? lifecycle-state check? Does the body decide a transition?

### C. Idempotency, retries, concurrency
- Is there check-then-act with an external call in between? Where is the "claim"?
- What is the real retry policy (max attempts, backoff) — prod/IaC export vs local value?
- Caller timeout vs downstream timeout: can the caller retry while the first call is still running?
- Does each retry create a new resource? Is there a unique index on a natural key?
- Does a handler return 4xx/5xx for "already running/done" that the queue will retry?

### D. Failure semantics & partial failure
- Is every error mapped to a terminal state even if the side effect may have occurred?
- Before re-issuing (invoice, payment, claim), does it check the downstream for an existing record?
- Multi-step operation: what is left half-done if step N fails? Rollback/compensation?
- Swallowed exceptions, retry on non-retryable errors.

### E. Messaging & scaling model
- nack on malformed/unknown messages → infinite redelivery? Dead-letter configured?
- Long-lived consumer (streaming pull, loops) inside a service that scales to zero?
- Ordering, duplication and poison-message handling.

### F. Data, indexes, migrations, time
- Index created lazily at runtime? Failed promise cached forever?
- Unique index missing a scope field (`db_name`, tenant)? Would the same migration be marked applied in all databases?
- Migration history collection name vs cleanup/backup filters.
- Can the migration run against every configured target? Is the guard validating against the configured value?
- `updated_at` from event time or other non-monotonic source.

### G. Configuration, tenants, environments
- Does a changed default affect tenants that did not ask for it? Is there a gate?
- Boolean env parsing: `== "true"` exact? Handles `True/TRUE/1`? Shared helper?
- Escape-hatch variables documented where they are read?
- Behavior matrix: tenant × env × flag → path. Any cell undefined or surprising?
- Local/dev fixtures updated for newly required keys (e.g. `jwt.secret`)?

### H. Naming & operational tooling
- New collection/table/queue/topic: does its name match or escape the filters in cleanup, backup, export, permission scripts (`startsWith("cfg_")`, globs, Makefile targets)?
- Could a documented "clean runtime" command delete data that must persist?

### I. Documentation, comments, tests drift
- Docstrings/comments that are now false? Notes referencing files that do not exist?
- Missing tests for: duplicate delivery, concurrency, malformed input, each target/tenant/flag variant, failure after side effect.

### J. Cross-repo & deployment coupling
- Does this PR require changes in another repo/service/config (dependent PR, new secret, new IAM, new index)? Is it listed?
- Does exported infra config differ from local config in a way that changes behavior?

### K. Architecture & complexity (baseline)
- I/O inside domain use cases, domain importing infrastructure.
- Complexity limits from `AI_RULES.md` §1; new nested loops; functions > 50 lines.
- `any`/loose casts, null paths, raw runtime errors where domain exceptions apply.

## 5. Finding Format (mandatory)

Every finding uses exactly this structure. A finding missing **Dónde** or **Escenario** must be dropped or moved to *Preguntas*.

```
### [HIGH|MEDIUM|LOW] <title stating the problem in one line>
- **Where:** file:line (only if visible in the diff) | "not visible in the diff — verify"
- **Evidence:** `<cited line(s) from the diff>`
- **Scenario (runtime):** <step-by-step what happens in production, with concrete values>
- **Why it is real:** <reachable path / precedent in the repo / config that triggers it>
- **Fix:** <concrete change; name the file/flag/index/state>
- **Blocking:** yes | no — <reason>  [PREEXISTING if applicable → suggest separate PR]
```

### Calibration examples

```
### [HIGH] `--target` does not work because db.py keeps DB_NAME fixed
- **Where:** migrations/utils/db.py (not modified in the diff); migrate.py calls get_db(args.target)
- **Evidence:** `DB_NAME = "rpas_v06"` + RuntimeError if names don't match
- **Scenario (runtime):** `make migrate TARGET=finmedic` → get_db raises RuntimeError before reaching the tracker. The service stays healthy (health 200) but /api/insurers returns count 0 and claims fail with CONFIG_ERROR.
- **Why it is real:** it is the reason why migration 20260831120002 never ran against rpaf even though the Makefile/README announce it.
- **Fix:** replace fixed DB_NAME with validation against target's `mongo_db` in db_targets.json; the guard still catches an outdated active_target.
- **Blocking:** yes — the announced feature is unreachable.
```

```
### [HIGH] RPA claim can be sent twice upon retry
- **Where:** SubmitRpaClaimUseCase lines 47–61
- **Evidence:** checks `claimId`, calls RPAS and only then claims the spot
- **Scenario (runtime):** RPAS takes >60s → rpa-submit returns 500 → Cloud Tasks retries (up to 100 attempts in the export; `maxAttempts: 3` only applies locally) → cfu_rpas creates a new Claim on each POST without a unique index on claim_ref → N actual claims.
- **Why it is real:** retry is normal queue behavior, not a rare edge case.
- **Fix:** unique index on claim_ref that returns the existing claim + mark `submission_pending` before calling RPAS.
- **Blocking:** yes.
```

```
### [LOW] Escape flag is compared with exact == "true"
- **Where:** <file:line>
- **Scenario (runtime):** BYPASS_CLOUD_TASKS=True or TRUE is silently ignored; time is wasted debugging.
- **Fix:** `.strip().lower()` or a shared boolean helper.
- **Blocking:** no.
```

## 6. Report Skeleton

```
## Change map
<Pass 0: files, changed defaults, new flags/vars, new indexes/collections, required config keys, affected tenants/targets>

## Findings
<findings ordered HIGH → MEDIUM → LOW>

## Questions for the author
<things that cannot be verified with the diff>

## Acceptable risks (if the author chooses not to block)
<list to paste into the PR's "Accepted risks" section: risk, scenario, owner, tracking>

## Verdict
Block | Approve with documented accepted risks | Approve
```

## 7. Anti-patterns (do NOT do this)

- Listing style nits when there are ALTO/MEDIO findings.
- Reporting "consider adding tests" without naming the exact missing case.
- Reporting hypothetical issues with no reachable path in the configured environments.
- Re-describing the diff.
- Assigning ALTO to anything without a concrete incident scenario.
- Inventing line numbers or file names.
- Treating `AI_RULES.md` complexity limits as more important than a duplicate-side-effect bug.