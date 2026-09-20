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
| `<RUN-HOME>` | the home directory of the container a scheduled run executes in (named in the scan paths of step 5b / 8a) |

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
| `daily-1200.txt` | daily check-in | `0 12 * * *` | 2026-09-20 |
| `evening-2300.txt` | evening reply check | `0 23 * * *` | 2026-09-20 |
| `weekly-mon-1100.txt` | weekly claim audit (no credential) | `0 11 * * 1` | 2026-09-20 |
| `monthly-neighbours.txt` | monthly neighbours check-in (read-only, ledger only) | `0 13 1 * *` | 2026-09-20 |

The column carries a date rather than a minute from 2026-09-20: a minute was
never checked by anything and had gone stale twice in one day without being
noticed, which is the argument against recording a precision nobody verifies.

**2026-09-20, daily and evening regenerated from the STORED bytes** — the toolkit pin moves from `da52f625` to `9a102ca0` (main, the merges of PR #52 and PR #53; signed tag `v2026.09.20.1`) so the runs execute the fixes from that day's code review. Step 1 of both: the commit in the fetch URL, `1f916-gate` `fc478d8a…` → `98fd1ae0…`, `1f916-scan` `38eb23e7…` → `d0b91b77…`, and the daily's `1f916-checks` `645ade16…` → `fa1594fc…`. `1f916-run` is byte-identical across the move. THREE of the four digests move here, where the two previous pin moves each moved one — the gate's read verb gained a path anchor and the scanner stopped treating a blank pattern line as a pattern matching everything, so those two files really did change. No other byte changed; both prompts are 34,441 and 18,198 bytes before and after, because a commit hash and a digest are replaced by strings of the same length. Byte-compared against the prepared bytes after `update_trigger`: both identical. `prompts/redact.py` re-proven first against the previous stored bytes, all four templates.

**The two revisions before it on the same day were applied and published but never recorded here**, and that is filled in rather than left as a hole. 2026-09-20, all four prompts: the slim `list_triggers` read, the daily's per-run `cost` block and the audit's weekly cost review (templates in PR #48). 2026-09-20, daily and evening: the pin move from `101288cb` to `da52f625` (templates in PR #49). Both regenerated the templates in this directory correctly; only this file was missed, which is why the table above had said 2026-09-17 while the published templates were two revisions newer.

**2026-09-17T12:4xZ, daily and evening regenerated from the STORED bytes** — the toolkit pin moves from `16aa4d23` to `101288cb` (merge of PR #43, signed tag `v2026.09.17.1`) so the runs execute the new `witness-gaps` rule and the `1f916-checks` hardening. Step 1 of both: the commit in the fetch URL; the daily's `1f916-checks` digest `da925665…` → `5b0ba8c0…`. `1f916-gate`, `1f916-run` and `1f916-scan` are byte-identical across the move. No other byte changed. Byte-compared after `update_trigger`: both identical (32,516 / 17,662 bytes). `prompts/redact.py` re-proven first against the previous stored bytes.

**2026-09-17T01:1xZ, daily, evening and weekly regenerated from the STORED bytes** — W40 candidate 8 option A: explanations, incident histories and justification clauses left the three prompts for the operator's ledger, each replaced by a one-token citation `(why: notes/<id>)` to a row that carries the reasoning (27 new rows, four existing). No instruction, threshold, field name, exit code or never/always clause was removed; spans that carry behaviour (an error string a run must recognise, the digest's worked example, a state that defines a finding) were kept. Daily 36,852 → 32,169 bytes, evening 19,370 → 17,662, weekly 22,725 → 19,917. Each byte-compared after `update_trigger`: identical. `prompts/redact.py` re-proven first: each previous stored prompt reproduces the previous template byte-for-byte.

**2026-09-17T00:1xZ, daily regenerated from the STORED bytes** — W40 item 7, one sentence in step 9(a), +108 bytes: posts, comments and citizens named in the digest carry the Observer link the operator's brief specifies (`https://1f916.observer/#/post/<id>`, `#/c/<id>` written beside its post as `c<id> in #<post id>`, `#/citizen/<handle>`), built only from ids the run read. The link convention itself lives in the brief, which the evening run and the weekly audit inherit, so their prompts are unchanged. The operator made the edit in the task's own editor; the stored prompt was then byte-compared with the prepared copy: identical (36,852 bytes). Template produced by `prompts/redact.py`, which was first re-proven to reproduce the previous template byte-for-byte from the previous stored bytes.

**2026-09-14T00:xxZ, daily and evening regenerated from the STORED bytes** — a second revision of W38 item 9, +523 bytes each in the previous-window step (daily 3k, evening 3f): a restart is not a second firing; compare `last_run.finished_at` against the clock the run is working on, because a hole between them is a session that died and was restarted by hand; `last_run.session_id` equal to the reading session's own id proves nothing, since a restart reuses it; record a rescued window as rescued. Prompted by the 2026-09-13 evening run reading its own restarted session's FAILED status as a contradiction. Byte-compared after `update_trigger`: both identical to what was sent (34,449 / 17,222 bytes). Templates produced by `prompts/redact.py`.

**2026-09-13T19:xxZ, three regenerated from the STORED bytes** (daily, evening, weekly) — the W38 batch, thirteen items the operator decided one by one. Daily: step 1 names three failure cells (hash mismatch, fetch denial with a reachability reading, classifier refusal) and reads the identity doc only after the tooling hashes match; the ack leaves the comments manifest and follows a re-read as its own act; the docket branch's position and both sides' newest migration number are read daily while PR #172 is open; the model step reads `model_correction.remaining` before correcting; the front map replaces rather than accumulates; a handle is resolved via the registry (and the ledger's `neighbours.aliases`) before a comment names it; lesson rows cite the open row they duplicate; a re-run of a third party's published method files an attestation-candidate row; and each daily run reads the other task's `last_run` from `list_triggers` and files a blocking row for a window with no runs row. Evening: the same, plus a step that reads the `/api/me` blocks no prompt had named (`credited_without_notice`, `named_in_window`, `your_record`, `standing.starter_items`) and `GET /api/me/history` for the previous UTC day. Weekly: the completeness check reads `last_run` beside a missing row, the prompt-integrity step gains a leak check over these templates, the capitalised-words grep pattern is scoped to docs, and the batch groups duplicate lesson rows under one line. Five operator-dated phrases and fine timestamps removed. The redaction that produces these files is now `prompts/redact.py` in this directory — placeholders only; the literals it replaces live in the operator's private project — and it was proven to reproduce all four prior templates byte-for-byte before it was used. Byte-compared after `update_trigger`: all three identical to what was sent (33,926 / 16,699 / 14,887 bytes).

**2026-09-07T21:xxZ, three regenerated from the STORED bytes** (weekly, daily, evening). The moving baselines and the front map left the project docs for a ledger `state` collection, so the daily's reads and writes and the weekly's compares point there; every run may file a `notes` row of kind `lesson` (observation and observable only) and the weekly gathers them, with a hygiene grep and the archive test, into one decision row for the operator — runs propose, only an attended sitting applies. The weekly no longer reads four history docs each week and carries no dated annotations; the change log is this repository's history and the ledger's `doc-change` rows. Byte-compared after `update_trigger`: all three identical to what was sent (11,838 / 25,616 / 9,186 bytes).

**2026-09-07T02:xxZ, daily and evening regenerated from the STORED bytes** after both were rewritten to use `1f916-run` (merged as PR #18, `fa2626b7`). What changed: step 1 fetches `1f916-gate`, `1f916-run` and `1f916-scan` pinned at that sha and checks their hashes before any credential is touched; the gate file and the scan-pattern file are written with the Write tool; the whole read phase (seal-check, pulse, inbox in id mode) is ONE `1f916-run … wake` call and every authenticated write is a step in a manifest run by `1f916-run … act`; the exit codes are the verdicts (2 mismatch, 3 not run, 4 registry failure, 5 key mismatch); a classifier refusal is retried once unchanged and then escalated, never reshaped; the continuity-core seal-check becomes the fresh-signature (possession-now) form; a scan-then-delete step (`5b` evening, `8a` daily) precedes RECORD with the exact expected result, rehearsed the same night. The old `sed`/`grep -rlf` fallback text is gone. Byte-compared after `update_trigger`: both identical to what was sent (24,808 and 8,821 bytes). New placeholder `<RUN-HOME>`.

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
`-witness.md`, `-registry-api.md`, `-intake-rules.md`, `-doc-editing.md`, `-identity.md`) and the
ledger's collections (`runs`, `board`, `queue`, `notes`, `queue-archive`, `state`, `prompts`); none of
those are in this repository, and the security ordering they enforce (identity doc → seal compare → load → act) is
described in the top-level README.
