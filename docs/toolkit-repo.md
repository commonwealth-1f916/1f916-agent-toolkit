# The published toolkit repo — `commonwealth-1f916/1f916-agent-toolkit`

Status: `queue/task-2026-09-20-toolkit-batch-1-pinned` (rev. 2026-09-20).

**Created 2026-09-02T02:3x–02:5xZ by the live Cowork session bridged to the Mac, at the operator's
instruction ("I think we should publish the code we're using to repos on the commonwealth-1f916
GitHub account... first, modify the code to abstract out any identifying information"), followed by
his follow-up instruction that changes be made **out of a GitHub clone so `git status` shows what
needs committing**. Repo name chosen by <OPERATOR-NAME> from two offered; README text agreed by <OPERATOR-NAME>.

https://github.com/commonwealth-1f916/1f916-agent-toolkit — public, MIT.

## 0. What this doc is for

The repo is now a **deployment source**, not an archive. Two machines symlink live files at it. So
this doc records the things a future session must not re-derive: what is deployed where, why the
config was externalised rather than redacted, what was verified, and what is still owed.

## 1. The central property, and every rule below follows from it

**The deployed file and the repo file are BYTE-IDENTICAL, structurally — because the deployed path
is a symlink into the clone, not a copy of it.**

    Mac       ~/bin/1f916-gate         -> ~/Projects/1f916-agent-toolkit/1f916-gate
    <WITNESS-HOST>  ~/bin/witness-alert.sh   -> ~/1f916-agent-toolkit/witness-alert.sh

Consequences, all of them load-bearing:

- **`git status` in either clone is a true statement about what is running.** That is the whole of
  what <OPERATOR-NAME> asked for, and a copy would only have promised it.
- **To change a deployed script you edit the clone, commit and push.** The Mac is the authoring
  host (it holds the `commonwealth-1f916` gh account); <WITNESS-HOST>'s clone is read-only in practice
  and updates with `git pull`. Never edit the deployed path directly — there is no deployed path
  any more, only the clone.
- **Nothing site-specific may enter these files.** Config lives outside the clone, in
  `~/.witness-alert.conf` on <WITNESS-HOST> (mode 600, listed in `.gitignore`) and in the `op run`
  invocation for the gate.

**The hazard this replaced, stated because it is the reason for the shape.** The first pass
(2026-09-02T01:5xZ) *redacted* the scripts for publication — vault id swapped for `<VAULT>`,
`TO`/`FROM` left hardcoded in the deployed copy. A clone whose working tree deliberately differs
from what you push is exactly the shape that leaks something the day someone runs `git add -A`, and
`run-witness.sh` already does `git add -A` hourly on <WITNESS-HOST>. **Redaction and externalisation are
the same work done wrong and done right.**

## 2. What is in the repo

| file | mode | notes |
|---|---|---|
| `1f916-gate` | 755 | the verify-then-load credential gate, v2 with the `post` verb |
| `witness-alert.sh` | 755 | the publisher/liveness alarm |
| `witness-alert.conf.example` | 644 | every site-specific value, documented |
| `README.md` | 644 | the argument; every quote and link fetched before it was written |
| `LICENSE` | 644 | MIT, copyright "commonwealth (1F916 citizen)" |
| `.gitignore` | 644 | `.witness-alert.conf`, `*.state`, `*.state.test` |

Commits (both authored **and** committed as `commonwealth`
`<321972176+commonwealth-1f916@users.noreply.github.com>`):

    83b6ca6902190a87548f3195bc3a0b4ae15c9161  tree 12b1b68188aeb7207aa717e348c1884b2c5a6597
      Initial: the gate and the witness alert this citizen actually runs
    c6aab1270b181b5bebdb66af879ce8572ec16783  tree 378e96f339c249bf8084caf0bded2274b1bdf38f
      Gate header: state the deployment requirement, not a mode number

## 3. How the push authenticated — do not re-derive this, it cost a wrong turn

**`gh` on the Mac holds TWO accounts in the keyring: `<OPERATOR-GITHUB-LOGIN>` (active) and `commonwealth-1f916`
(inactive), both with `repo` scope.** *(Dated 2026-09-07: this line was undated for five days.
Machine read at 17:0xZ, freeze-then-verify, login asserted: the machine account's token carries
`gist, read:org, repo, workflow` and NOT `admin:ssh_signing_key`; active account confirmed back at
`<OPERATOR-GITHUB-LOGIN>`. `claude/1f916-signing-key-setup.md` owns the consequence — the signing key was registered
through the browser, not by `gh auth refresh`. Scopes change when a token is refreshed or revoked, so
re-read rather than inherit either line.)* A session checked `gh api user`, saw <OPERATOR-GITHUB-LOGIN>, and concluded
no commonwealth credential existed anywhere — <WITNESS-HOST> has no `.git-credentials`, no `gh`, no
`.netrc`, and pushes the witness repo over SSH as <OPERATOR-GITHUB-LOGIN>. **<OPERATOR-NAME> corrected it: "I do believe we
have a credential that we've used previously for that account. Can you check again?" `gh auth
status` lists both.**

    gh auth switch --user commonwealth-1f916     # act
    gh auth switch --user <OPERATOR-GITHUB-LOGIN>                # ALWAYS switch back

**The commit identity is handled separately and automatically** by `~/.gitconfig-1f916`, included
via `hasconfig:remote.*.url:https://github.com/commonwealth-1f916/**`. It fires on the clone's
remote URL, so a clone made anywhere gets `commonwealth` as name and the noreply address as email.
**<OPERATOR-GITHUB-LOGIN> appears in no commit object that a session authored** — only in GitHub's pusher event, which is already public
via `<WITNESS-REPO>`. *(Corrected 2026-09-05: since 2026-09-04 this is no longer true of every commit — GitHub-UI merge commits are authored by the operator, and since 2026-09-05 commits pushed through the GitHub connector carry <OPERATOR-GITHUB-LOGIN>'s noreply identity. The machine account also merged homepage PR #2 by accident on 2026-09-04, harmlessly. §8.)*

**Lesson for the record: "I checked and found no credential" was a check of the ACTIVE account
reported as a check of the machine.** Same shape as *a baseline is a tripwire, not a reading*.

## 4. Verification performed

**Transfer (container → Mac), three independent levels.** Tarball sha-256
`d2fe74b8820c938403f624b3d6bdaa704c3bef41ebf187d1a9e2f4f7263ccee9` asserted on arrival before
extraction; all six per-file digests compared against the container's; and the Mac's commit tree
came out `12b1b68…` — **identical to the tree git computed independently in the container**, which
is a content match nobody had to transcribe.

**Publication, anonymously.** All six files re-fetched from `raw.githubusercontent.com` with no
auth; all six digests matched the local ones.

**Every README link and quote fetched before it was written.**
- `#827` is @verbatim, and *"anything the agent must never emit should be a thing the agent never
  receives"* is byte-exact in the post body.
- `c24243` is @holdfast on post #1002, and *"signing my seal preimage 50 times produces 1 distinct
  signature, byte-identical to the one already published"* is byte-exact.
- ⚠ **A credit was wrong and was dropped rather than guessed at.** A prior session's note said to
  credit "@unspent c3044". **c3044 is @pi-agent, on post #484, about the constant-as-mechanism
  trap** — a different author on a different subject. There is no way to know which comment was
  meant, so the credit was removed. If the intended @unspent comment is identified later it can be
  added.
- ⚠ **The board has no public `/thread/` or `/post/` web URLs.** `https://1f916.ai/thread/827`,
  `/post/827` and `/p/827` all 404. Only `/api/post/:id` and `/api/comment/:id` answer 200. **Any
  future artifact that links to the board must use the `/api/` paths**, and the README says so.

**Gate acceptance, six tests, no credential and no 1Password unlock**, re-run against the symlink
after deployment: no inputs → exit 3 naming all four · unknown verb → exit 3 · off-allowlist path →
exit 3 · **`/api/rotate` → refused** · missing body file → exit 3 · **valid shape + wrong
credentials → exit 2 MISMATCH against the live `989856af…`, no authenticated call**.

**Alert acceptance on <WITNESS-HOST>, ending in a real delivery.** Forced exercise with
`WITNESS_ALERT_TEST=1 WITNESS_STALE_HOURS=0` against the real repo produced
`[1F916][TEST] witness #6 needs attention on <WITNESS-HOST>`, **received in the Fastmail `1F916` folder at
2026-09-02** with the FORCED EXERCISE banner. The **real** state file was never written
(only `.state.test`, since removed); a normal run afterwards was silent and exited 0; and
`WITNESS_ALERT_CONF=/nonexistent` still exits 3. **The crontab was not touched** — the symlink keeps
`12 * * * * <RUN-HOME>/bin/witness-alert.sh` byte-identical, and `run-witness.sh` and the sealed
`7 * * * *` line were never opened.

## 5. What changed in the scripts, and why

**`witness-alert.sh` 4,047 → 5,252 bytes**, sha-256
`1eb6814f3cc198682bbdb45344d9b8d3feab9c46f92171c6bb8a606566acc723`. Backup of the deployed original
at `~/bin/witness-alert.sh.bak-20260902` on <WITNESS-HOST>.

Config surface, all read after the conf is sourced so any of them can be overridden:
`WITNESS_ALERT_CONF` · `WITNESS_REPO` · `WITNESS_ALERT_TO` · `WITNESS_ALERT_FROM` · `WITNESS_ID` ·
`WITNESS_STALE_HOURS` · `WITNESS_LOG_STALE_MINUTES` · `WITNESS_ALERT_STATE` · `WITNESS_ALERT_TEST`.

Three behavioural additions:
- **It refuses to run (exit 3) when `TO` or `FROM` is unset.** *An alarm with no destination is
  silence that looks like health* — the same rule the gate applies to empty credentials.
- **`WITNESS_ID` labels the subject.** Set → `witness #6`, unset → `witness`. **The live conf sets
  `WITNESS_ID=6`, which is what keeps the subject byte-identical to what both scheduled prompts
  expect.** Changing or unsetting it silently breaks the prompts' intake rules.
- **Two thresholds are now configurable** (`STALE_HOURS`, and the previously hardcoded 90-minute
  log check). The example conf says to set them from the row's **observed** cadence, not from what
  the cron line claims — those are different facts.

Two ordering defects found and fixed during the rewrite, both of which would have silently
neutralised the externalisation: a leftover `STALE_HOURS=3` after the config block that overrode
`${WITNESS_STALE_HOURS:-3}`, and the `TESTMODE`/`STATE` derivation sitting **above** the config
source.

**`1f916-gate` 6,293 → 6,295 bytes** in the repo, sha-256
`5de90cde35b6b117f3ee70d559a6e92e5016175b26b4a920b4d40d8f70c014e9` after the header fix (the
6,293-byte operational v2 is preserved at `~/bin/1f916-gate.bak-20260902-preclone`, and v1 at
`~/bin/1f916-gate.bak-20260902`). **Only three executable lines differ from the operational v2, and
all three are improvements:** `SEALS_URL` is derived from `$HANDLE` instead of hardcoding
`commonwealth`; its assignment moved below the input check so `set -u` cannot abort before the check
can name what is missing; and the mismatch message says *tell your operator* rather than a name.
**Everything else that differed was comments** — the vault path appeared only in the header's `op
run` examples, never in a code path, so the gate needed no config file at all.

The header's `mode 700` claim was rewritten in the second commit. A file living in a clone is 755,
so deploying by symlink would have made a published claim false at the moment of carrying it out.

## 6. What is owed, and what is NOT

**OWED — a board comment, and it is in `claude/1f916-state.md`'s `OWED ON THE BOARD` block.** The
README names @verbatim and @holdfast and attributes arguments to them in a public artifact they did
not choose. That is the same shape that created PR #2's debt: *your named words now represent you in
a venue you did not pick*, and one attribution in the first draft was already wrong. Lowest priority
of the three items in that block; either thread may be answered first.

**NOT owed — the repo's mere existence.** It publishes this household's own scripts, makes no claim
about anyone else's machine or data, and asserts nothing a stranger would need to check on their own
behalf. Recorded so the verdict exists rather than the silence.

**NOT owed — the deployment.** No public artifact moved; the symlinks are local facts.

## 7. Standing rules a future session must not violate

1. **Never edit `~/bin/1f916-gate` or `~/bin/witness-alert.sh`.** They are symlinks. Edit the clone,
   commit, push, and `git pull` on <WITNESS-HOST>.
2. **Never put a site-specific value in a tracked file.** If a new one appears, add it to the
   config surface and to `witness-alert.conf.example`, never inline.
3. **`gh auth switch --user <OPERATOR-GITHUB-LOGIN>` after any commonwealth-account work.** It was left switched
   back on 2026-09-02; verify with `gh api user --jq .login` rather than assuming.
4. **The clone on <WITNESS-HOST> must stay OUTSIDE `~/1f916-witness`** (it is at `~/1f916-agent-toolkit`),
   because `run-witness.sh` runs `git add -A` hourly and would publish anything inside it.
5. **`run-witness.sh` and the `7 * * * *` cron line are still untouchable** — inputs to seal 1809
   and the daily 3(c) check. Nothing in this repo touches either, and that is deliberate.
6. **A change to `witness-alert.sh` is a change to a live alarm.** Fire
   `WITNESS_ALERT_TEST=1 WITNESS_STALE_HOURS=0 ~/bin/witness-alert.sh` afterwards and confirm the
   mail lands in the Fastmail `1F916` folder, then remove `~/.witness-alert.state.test`. Structural
   checks are not sufficient: the only thing worth proving is that an alarm still reaches a person.
7. **If the README's byte-identical claim ever stops being true, fix the deployment or fix the
   README in the same sitting.** It is a published claim about a live system and it is checkable by
   anyone with shell access to either machine.

## 8. Branch protection — `main` is enforced, not just promised (2026-09-05)

Ruleset **"Main"** (id 22346622), active, target `~DEFAULT_BRANCH`, **no bypass actors** (it binds
<OPERATOR-NAME> too). Read back through the API from the Mac the minute it was saved, so this is the stored
state rather than what the form showed:

- `deletion` blocked; `non_fast_forward` blocked — brief rule 6 as a mechanism.
- `pull_request` required: 0 approvals, allowed merge methods **`merge` only** (squash and rebase
  rewrite the PR's commits into new SHAs; cited SHAs and signed commits must land as-is).
- `required_status_checks`, **strict** (branch must be up to date with `main` before merge — the #8
  lesson, where green checks from an old base predated the hygiene job): `shellcheck`,
  `hygiene (macos-latest)`, `hygiene (ubuntu-latest)`, `gate-tests (macos-latest)`,
  `gate-tests (ubuntu-latest)`, `checks (ubuntu-latest)`, `checks (macos-latest)`, each pinned to
  the GitHub Actions integration (`integration_id` 15368). The two `checks` rows were added
  2026-09-20 and read back from the API in the same command; until then a red `tests/test_checks.py`
  did not block a merge, which is what `1f916-checks` shipping with PR #38/#39 had quietly assumed
  (why: `notes/2026-09-20-doc-change-ruleset-requires-the-checks-job`) (rev. 2026-09-20).
  **`alert` and `mutants` are NOT jobs** — they are steps inside `gate-tests`
  (`.github/workflows/ci.yml` lines 100 and 102), so a required check by those names would never
  report and would block every merge; two such rows were removed before saving.

Why now: as of 2026-09-05 the GitHub connector writes to this repo as <OPERATOR-GITHUB-LOGIN> with no human in the
loop during a scheduled run (§3 correction above; delivery runbook), so "never any repo's `main`,
never force-push" had become a rule the run follows rather than one the repo enforces. The ruleset
makes the repo refuse what the prompt forbids. <OPERATOR-NAME>: *"I think the toolkit is the key branch to
have protected."* The homepage repo and the fork are unprotected as of this date; the same shape
would fit the homepage (where a merge without its seal is the failure the 12:00 run watches for),
and on the fork the branch that matters is `claude/custody-declare` (deletion + non-fast-forward
only; it is pushed to directly).

Consequences for sessions: a PR merges only with seven green checks on an up-to-date base; a stacked
PR must be brought up to date after its parent merges; `required_status_checks` names are the CI
job names — renaming a job in `ci.yml` silently strands the ruleset until it is edited to match.
