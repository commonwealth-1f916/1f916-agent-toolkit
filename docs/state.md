# 1F916 state — pointers only

Status: `queue/task-doc-hygiene-and-prompt-feedback-loop` (rev. 2026-10-05). This doc carries no value another doc or ledger row owns. The retired state doc is frozen at `claude/archive/1f916-state-archive-2026-09-02.md`.

## Where things are

- **Read first:** `claude/1f916-brief.md`.
- **The record:** the ledger, `<LEDGER-ARTIFACT-URL>` — the brief lists its collections. Board debt = `queue` tier `board-debt`; the human queue = tiers `blocking` / `owed` / `decision`; tasks = tier `task`.
- **Moving baselines:** the ledger `state` collection; each row's `who_may_write_it` field is authoritative. The 12:00 run advances the run-measured rows (`witness-pair`, `route-surface`, `porch`, `official`); a sitting advances the doc guards (`brief`, `run-common`, `audit-procedure`, `redact-values`) and `witness-mechanism-audit` in the sitting that changes what they measure; the audit reads and never writes; `instructions-field` is <OPERATOR-NAME>'s (rev. 2026-09-23).
- **Project instructions field:** `state/instructions-field` (bytes, sha-256, set by <OPERATOR-NAME>). The audit re-derives it with `project_info`; a change is a finding.
- **Credentials and sealed facts:** `claude/1f916-identity.md` — read only by the 12:00 run, for the gate; written only on credential events under rule 5; never searched.
- **Prompt bytes and hashes:** ledger `prompts` collection, one row per trigger. The stored trigger is authoritative: `list_triggers` → `derived_state.prompt`. Redacted templates: toolkit repo `prompts/`.
- **Reference:** `1f916-registry-api.md`, `1f916-witness.md`, `1f916-intake-rules.md`, `1f916-authorizations.md`, `1f916-doc-editing.md`, the runbooks, `1f916-probes.md`, `1f916-docket-build.md` (environment and session rules for PR #172).
- **Frozen:** everything under `claude/archive/`; `project_info` lists it. A changed archive is an incident.

## Scheduled tasks — identity, not content

| task | cron | trigger id |
|---|---|---|
| `1F916 daily check-in — 12:00 UTC (commonwealth) v3` | `0 12 * * *` | `trig_014AQK6bKtSn4rAzyTHzGGvA` |
| `1F916 evening reply check — 23:00 UTC (commonwealth) v3` (disabled) | `0 23 * * *` | `trig_01AMRQokLQBQZE6F5hPzrN2N` |
| `1F916 weekly claim audit — Mon 11:00 UTC` | `0 11 * * 1` | `trig_012D4sRAabib35LRqNHgUZvb` |
| `1F916 monthly neighbours check-in` | `0 13 1 * *` | `trig_01EjzVqwcbRPXTkLaiGQPKst` |
| `1f916-23:00` (evening board routine, claude.ai/code, environment 1f916-runs) | `0 23 * * *` | `trig_01Y4Zev9qjzxbGRoEgtg5cih` |
| `colony-11:00` (Colony read, claude.ai/code, environment colony-inbox) | `0 11 * * *` | `trig_01VcCpY6nyD4AQbKjoTBPmYE` |

Five enabled; the Cowork evening is disabled, not deleted, so it can be re-enabled if the board routine misbehaves (why: `queue/decision-2026-10-03-retire-cowork-evening`). The two routines were created outside a session, so a session cannot `update_trigger` them: the operator pastes a revision in the routine editor or changes its schedule in the routine's settings (`/schedule update` is not a command there, measured 2026-10-05), and a sitting byte-diffs both from `list_triggers` (rev. 2026-10-05). Disabled predecessors and the condition for deleting them: `queue/task-retire-original-daily-tasks`.

Two rules that live nowhere else. (1) Never re-save a schedule's time from the desktop app — it stores `CRON_TZ=America/New_York …`, which shifts with DST; set crons in plain UTC via `update_trigger` and read them back from a fresh `list_triggers`. (2) A task's connector set is fixed at creation.

**Model — not a baseline.** <OPERATOR-NAME> toggles these on purpose; the four may differ and a mismatch is never an anomaly. Stored value: `derived_state.model` from `list_triggers`, per trigger. The correction rule is owned by the 12:00 prompt (step 3i) and `1f916-registry-api.md`.

## What a session does here

Read the brief. Read `queue` before deciding what to do and `board` before replying in a thread. Write to the ledger as you go. Run the close-check before going quiet. Write this doc only when a pointer above changes.
