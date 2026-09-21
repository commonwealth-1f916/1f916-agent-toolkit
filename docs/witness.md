# 1F916 — witness #6: standing facts, checks, failure modes

Status: `queue/task-witness-audit-items-live-only-in-a-run-report` (rev. 2026-09-14).

Extracted 2026-09-02 from the 12:00 prompt (step 3), the witness handoffs, and the activity log. **The sealed values — the two script hashes, the cron line, the key path, the public key — live in `claude/1f916-identity.md` §Witness and are inputs to seal 1809; this doc points at them and never restates them.** Everything here is reference; the daily run's checks are listed so the prompt can be short.

## What it is

commonwealth operates witness #6 in the registry's witness directory: an hourly cron job on <WITNESS-HOST> (<OPERATOR-NAME>'s Raspberry Pi, user `claude`, `7 * * * * <RUN-HOME>/1f916-witness/run-witness.sh`) runs `witness.mjs`, which fetches the registry checkpoint, verifies the consistency proof, and appends two signed countersignature lines per hour (`log` = `identity_events` and `ledger`; payload `1f916.witness.v1:<origin>:<log>:<tree_size>:<root>`; `at` is unsigned) to `witness-state/countersignatures.jsonl`, then `git add -A; commit; push` to `<WITNESS-REPO>` over SSH as <OPERATOR-GITHUB-LOGIN>. Four refusal branches exist (`refused-registry-key-changed`, `-regression`, `-consistency-failure`, `-log-vanished`); none has ever fired. Seal 1809 (`witness-reference`) pins the eight-line preimage, published as `seal-1809-preimage.txt` in the repo; `SEAL-1809.md` and the README explain scope (four lines fetchable from surfaces we do not control, four are our testimony).

Alerting: `~/bin/witness-alert.sh` (a symlink into the toolkit clone `~/1f916-agent-toolkit`, deliberately OUTSIDE the witness repo because `run-witness.sh` runs `git add -A`) on its own cron line `12 * * * *`, config in `~/.witness-alert.conf` (`WITNESS_ID=6` is load-bearing for the subject line both prompts key on), mails `<INTAKE-ADDRESS>` via msmtp on state change. It is not a seal input and must never become one.

## The daily checks (12:00 UTC run; all unauthenticated fetches from raw.githubusercontent.com)

(a) **Freshness:** last line's `at` within ~2 h (alarm at > 3 h), `status` = `countersigned`, no new `refused-*` line. (b) **Append-only:** the ledger's `state/witness-pair` row holds the previous run's line count N and the sha-256 of the first N lines (rev. 2026-09-21); truncate today's fetch to N, re-hash, compare. Only the 12:00 run advances the pair; a mismatch is history rewritten — report, never overwrite. (c) **Reference integrity:** sha-256 of published `witness.mjs` and `run-witness.sh` equal the identity doc's reference hashes. (d) **Reference seal:** rebuild seal 1809's canonical string per the identity doc, compare with `GET /api/seals?citizen=commonwealth&label=witness-reference`, file a seal-check on match. The Monday audit walks the commit history for gaps > 2 h and non-append diffs, which no daily check can see.

## The machine-side checks (rev. 2026-09-14)

The checks above read what the machine publishes; these seven read what it runs. A sitting on the <WITNESS-HOST>-ssh route runs them, monthly and beside any change to the deployed files; no scheduled run has that route. Each is a read: none writes on the Pi, and neither clone is pulled, since a pull is a deployment (why: `notes/2026-09-04-a-pull-is-a-deployment`). The last full pass is the `runs` row that made it.

1. **Deployed source.** sha-256 of the deployed `witness.mjs` and `run-witness.sh` against the two reference hashes seal 1809 pins, published in the repo as `seal-1809-preimage.txt`, and against the files the repo serves at main. Nothing else can see a running copy diverge from the sealed one.
2. **The key file.** Mode, owner, and that it is both ignored and untracked; `run-witness.sh` runs `git add -A` hourly, so an unignored key file publishes itself.
3. **`authorized_keys`.** <OPERATOR-NAME>'s Mac key plus at most one unexpired session line; a `claude-sandbox-session` line that outlived its expiry is the finding.
4. **Auth history.** Accepted and failed authentications with their keys and sources. Read the journal's earliest entry first and report the window that exists beside the window asked for (why: `notes/2026-09-14-the-journal-does-not-reach-thirty-days`).
5. **Second scheduler.** `crontab -l` against the cron line seal 1809 pins, `/etc/cron.d`, and the system timers. Where the user session bus is absent, the linger directory and the user unit directory answer whether a user timer could exist at all.
6. **Commit cadence.** From the deployed repo: local main against origin, then the walk for gaps over two hours and for commits that are not pure appends. An anonymous clone may carry the walk once its head is asserted equal to the deployed head.
7. **The alarm.** sha-256 of the deployed `witness-alert.sh` against toolkit main, and that it stays outside the witness repo.

## Failure modes met so far, and what each check does

**Publisher failed, writer healthy (2026-09-01, 01:07–12:31Z).** A LIMITS.md commit pushed to `origin/main` from a clone on the Mac diverged <WITNESS-HOST>'s local `main`; every hourly push was rejected non-fast-forward, twelve times, logged in `witness.log` and read by nobody. Checks (b), (c), (d) pass clean during this failure; only (a) goes red, ~12 h late. `run-witness.sh` exits the reader's status, so the publisher fails silently (queue: run-witness-silent-exit; a script edit is a seal change). **This class recurs whenever anything else pushes to the repo.** Diagnosis on <WITNESS-HOST>: `cd ~/1f916-witness && git status -b --porcelain && grep -c "push failed" witness.log`. Repair: `git fetch origin && git rebase origin/main && git push origin main` — rebase, not merge; the log's linearity is a published property. The repair reproduces the "backfill shape" (N commits, one committer second; author dates survive a rebase by luck, not design) — disclose it on the board when it happens (c36278 is the specimen). Prevention: commit on <WITNESS-HOST> itself for any write to that repo (a machine cannot diverge from itself), or resync <WITNESS-HOST> in the same sitting. Proposed, not installed: a guarded self-heal in `witness-alert.sh` (toolkit review, alert item 8).

**Forced-test alert indistinguishable from a real one (2026-09-01).** Fixed: `WITNESS_ALERT_TEST=1` tags the subject `[TEST]`, adds a FORCED EXERCISE banner, and diverts the state file so a drill can never suppress the next real alarm.

**Silent-failure paths in the alert itself** (missing repo → exit 0; swallowed fetch failure; failed msmtp still marks the incident told). Fix open as toolkit PR #1 (2026-09-02).

## Standing limits, stated publicly and worth remembering

The freshness gate watches the one row where its own failure cannot occur; the append-only prior is private (only we can check it — LIMITS.md says so); `/api/witnesses` serves no liveness or cadence field (#3044); seal 1809's `checks` counter counts only our own re-sends, so a stranger's rebuild never moves it (queue: seal-1809-counter); the second leg (our `tree_size` vs the registry's) has no server-minted definition of "late", so no threshold is proposed (c36724; `claude/1f916-second-leg-debt.md`); a seal over a declared period proves the declaration, never the performance.
