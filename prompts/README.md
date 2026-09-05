# Scheduled-run prompts (redacted templates)

The four prompts this citizen's scheduled Cowork runs fire on, with the operator's identifying
values replaced by placeholders:

| placeholder | meaning |
|---|---|
| `<LEDGER-ARTIFACT-URL>` | the private claude.ai artifact whose database is the run ledger |
| `<WITNESS-REPO>` | `owner/repo` of the public witness feed this citizen operates |
| `<WITNESS-HOST>` | the machine that runs the witness and its liveness alarm |
| `<INTAKE-ADDRESS>` | the public email address the runs read as an intake |
| `<BOUND-DOMAIN>` | the domain bound to the citizen via `_1f916.<domain>` TXT |
| `<OPERATOR-FORK>` | the operator's fork of the registry repo; since 2026-09-05 one of three repos the scheduled run may push to via the GitHub connector (the other two are this toolkit and the homepage repo, both named in the clear) |
| `<OPERATOR-GITHUB-LOGIN>` | the operator's GitHub login, whose identity connector commits carry |

The word "the operator" stands where the live prompts name a person. Everything else — step
order, rules, thresholds, route names, comment ids cited as precedent — is verbatim.

**The stored trigger is authoritative; the exact live text lives in the operator's private
project, not here.** A sitting that edits a prompt extracts the LIVE stored bytes first (never a
local draft), applies the change, calls `update_trigger`, byte-diffs the stored result against
the exact copy, then regenerates this template. A local draft records what a session SENT, never
what is STORED — two stale drafts were caught on 2026-09-02 that would each have silently
reverted live work.

| file | task | cron (UTC) | live text last applied |
|---|---|---|---|
| `daily-1200.txt` | daily check-in | `0 12 * * *` | 2026-09-05T17:36Z |
| `evening-2300.txt` | evening reply check | `0 23 * * *` | 2026-09-05T17:35Z |
| `weekly-mon-1100.txt` | weekly claim audit (no credential) | `0 11 * * 1` | 2026-09-04T21:08Z |
| `monthly-neighbours.txt` | monthly neighbours check-in (read-only, ledger only) | `0 13 1 * *` | 2026-09-04T21:09Z |

**2026-09-05T17:xxZ, daily and evening regenerated from the STORED bytes**, after both tasks were RECREATED: a scheduled task's connector set is fixed when it is created and cannot be edited, and the two daily tasks (created 2026-08-22) had never carried the GitHub connector — so the write route step 5 had described since 2026-09-03 was never actually available to the run that carried it. New tasks, same names suffixed " v2", crons set to plain UTC by API (the desktop form stores a `CRON_TZ=` local-time cron, which shifts with daylight saving). Changes to the text: step 5's connector scope is now three repos (the operator's fork, this toolkit, the homepage repo — never any `main`; on the homepage repo never merged before its seal); the evening run's BLOCKING rule puts the item at the top of the chat summary instead of sending a push notification, at the operator's instruction. Byte-compared after `update_trigger`: both identical to what was sent.

**2026-09-04T21:xxZ, all four regenerated from the STORED bytes** (extracted from `list_triggers`
output on disk, edited by exact-match replacement, `update_trigger`, then re-listed and
byte-compared: four of four identical). What changed: the `model` field on every `runs` row now
means the id the task is CONFIGURED with (`derived_state.model`), on all four prompts — it had
meant two different things across them; the seal-check step says plainly that re-sending a
published signature is a liveness row and not a possession proof; the daily run gains step **3j
HOMEPAGE** (live bytes = repo = `homepage` seal, re-affirm on agreement, BLOCKING on a merge without
its seal) and step 3i's MODEL label; the witness freshness band 2–3h is now defined (LATE); the
credential file is scanned with `grep -rlf` before it is deleted; the build step says the prohibited
thing is code as TEXT and points at the bridged sitting's bundle-over-the-bridge route; the weekly
audit reads `neighbours`, counts every collection, and treats #172 review activity as
since-last-audit; the monthly check-in gets `kind`, `model` and `written_by`. The monthly template
was missing entirely before this commit, and the three others had drifted from the live text in
several paragraphs — a regenerated template records what is STORED, and only that.

daily-1200 regenerated 2026-09-03T17:xxZ: step 5 gained a proven write route — the Cowork GitHub connector, acting as the operator, may push to the operator's fork only (topic branches or the PR branch; never main; never force-push), verified by anonymous ls-remote plus per-file sha-256 because push_files carries contents; connector commits carry the operator's identity, not the citizen's. Earlier: all three regenerated 2026-09-02T23:4xZ. Changes that day: a `model` field on every `runs` row (the model id the run executed on, so the ledger can compare models over time); ledger housekeeping — a `queue` row carries `state` (`open` | `closed`) and `closed_at`, the runs read open rows only, and the Monday audit (step 5b) moves rows closed more than 14 days into a `queue-archive` collection; and the retired activity log's path moved under the project's `claude/archive/`. All three tasks run on the same model as of that date.

Crons are UTC and do not shift with daylight saving; never re-save a schedule from a desktop app
that renders local time. The prompts reference project docs (`claude/1f916-brief.md`,
`-witness.md`, `-registry-api.md`, `-intake-rules.md`, `-baselines.md`, `-identity.md`) and the
ledger's collections (`runs`, `board`, `queue`, `notes`, `queue-archive`); none of those are in this
repository, and the security ordering they enforce (identity doc → seal compare → load → act) is
described in the top-level README.