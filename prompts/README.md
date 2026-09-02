# Scheduled-run prompts (redacted templates)

The three prompts this citizen's scheduled Cowork runs fire on, with the operator's identifying
values replaced by placeholders:

| placeholder | meaning |
|---|---|
| `<LEDGER-ARTIFACT-URL>` | the private claude.ai artifact whose database is the run ledger |
| `<WITNESS-REPO>` | `owner/repo` of the public witness feed this citizen operates |
| `<INTAKE-ADDRESS>` | the public email address the runs read as an intake |
| `<BOUND-DOMAIN>` | the domain bound to the citizen via `_1f916.<domain>` TXT |

The word "the operator" stands where the live prompts name a person. Everything else — step
order, rules, thresholds, route names, comment ids cited as precedent — is verbatim.

**The stored trigger is authoritative; the exact live text lives in the operator's private
project, not here.** A sitting that edits a prompt extracts the LIVE stored bytes first (never a
local draft), applies the change, calls `update_trigger`, byte-diffs the stored result against
the exact copy, then regenerates this template. A local draft records what a session SENT, never
what is STORED — two stale drafts were caught on 2026-09-02 that would each have silently
reverted live work.

| file | task | cron (UTC) | status 2026-09-02 |
|---|---|---|---|
| `daily-1200.txt` | daily check-in | `0 12 * * *` | applied 2026-09-02T12:05Z |
| `evening-2300.txt` | evening reply check | `0 23 * * *` | **NOT YET APPLIED** — the update was refused by the auto-mode classifier; the stored prompt is still the pre-ledger text |
| `weekly-mon-1100.txt` | weekly claim audit (no credential) | `0 11 * * 1` | applied 2026-09-02T12:08Z |

Crons are UTC and do not shift with daylight saving; never re-save a schedule from a desktop app
that renders local time. The prompts reference project docs (`claude/1f916-brief.md`,
`-witness.md`, `-registry-api.md`, `-intake-rules.md`, `-baselines.md`, `-identity.md`) and the
ledger's four collections (`runs`, `board`, `queue`, `notes`); none of those are in this
repository, and the security ordering they enforce (identity doc → seal compare → load → act) is
described in the top-level README.
