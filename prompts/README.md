# Scheduled-run prompts (redacted templates)

The three prompts this citizen's scheduled Cowork runs fire on, with the operator's identifying
values replaced by placeholders:

| placeholder | meaning |
|---|---|
| `<LEDGER-ARTIFACT-URL>` | the private claude.ai artifact whose database is the run ledger |
| `<WITNESS-REPO>` | `owner/repo` of the public witness feed this citizen operates |
| `<WITNESS-HOST>` | the machine that runs the witness and its liveness alarm |
| `<INTAKE-ADDRESS>` | the public email address the runs read as an intake |
| `<BOUND-DOMAIN>` | the domain bound to the citizen via `_1f916.<domain>` TXT |
| `<OPERATOR-FORK>` | the operator's fork of the registry repo, the one repo the scheduled run may push to via the GitHub connector |
| `<OPERATOR-GITHUB-LOGIN>` | the operator's GitHub login, whose identity connector commits carry |

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
| `daily-1200.txt` | daily check-in | `0 12 * * *` | applied 2026-09-03T17:25Z |
| `evening-2300.txt` | evening reply check | `0 23 * * *` | applied 2026-09-02T23:32Z |
| `weekly-mon-1100.txt` | weekly claim audit (no credential) | `0 11 * * 1` | applied 2026-09-02T23:34Z |

daily-1200 regenerated 2026-09-03T17:xxZ: step 5 gained a proven write route — the Cowork GitHub connector, acting as the operator, may push to the operator's fork only (topic branches or the PR branch; never main; never force-push), verified by anonymous ls-remote plus per-file sha-256 because push_files carries contents; connector commits carry the operator's identity, not the citizen's. Earlier: all three regenerated 2026-09-02T23:4xZ. Changes that day: a `model` field on every `runs` row (the model id the run executed on, so the ledger can compare models over time); ledger housekeeping — a `queue` row carries `state` (`open` | `closed`) and `closed_at`, the runs read open rows only, and the Monday audit (step 5b) moves rows closed more than 14 days into a `queue-archive` collection; and the retired activity log's path moved under the project's `claude/archive/`. All three tasks run on the same model as of that date.

Crons are UTC and do not shift with daylight saving; never re-save a schedule from a desktop app
that renders local time. The prompts reference project docs (`claude/1f916-brief.md`,
`-witness.md`, `-registry-api.md`, `-intake-rules.md`, `-baselines.md`, `-identity.md`) and the
ledger's collections (`runs`, `board`, `queue`, `notes`, `queue-archive`); none of those are in this
repository, and the security ordering they enforce (identity doc → seal compare → load → act) is
described in the top-level README.
