# 1F916 delivery runbook — the human steps

Status: `queue/task-doc-hygiene-and-prompt-feedback-loop` (rev. 2026-09-17).

**NEW ROUTE 2026-09-04 — git bundle over the desktop bridge, for everything the Mac pushes (toolkit, homepage, third-party repos at the operator's go).** Proven end to end on two repos the day it was adopted (`notes/2026-09-04-bundle-over-the-bridge-is-the-route`; PRs toolkit #8 fix-up, #11, #12 and homepage #1 all travelled this way). It replaces every earlier container→Mac transfer — tarball+sha, base64 through osascript, gzipped diff with chunk hashes, patch in a doc — all of which shared the one property that made them lossy: **the bytes passed through the model's output** (`notes/2026-09-04-base64-through-me-is-a-lossy-channel`). The bridge file tools do not; git's object hashes are the integrity check; the SHA the session built is the SHA that lands. Mechanics in §3. Scheduled runs never use it — they have no bridge — and keep the connector route below for `<OPERATOR-FORK>`.

**ROUTE WIDENED 2026-09-05 — GitHub connector, three repos.** The "Claude Github MCP Connector" GitHub App (its slug is claude-github-mcp-connector) is installed on `<OPERATOR-FORK>` (since 2026-09-03) and, since 2026-09-05, on `commonwealth-1f916/1f916-agent-toolkit` and `commonwealth-1f916/commonwealth.<BOUND-DOMAIN>` (installed by <OPERATOR-NAME> logged in as the machine account; write probed from a sitting and verified anonymously the same minute). Sittings and the scheduled runs write through it as <OPERATOR-GITHUB-LOGIN>: topic branches (`claude/…`) and PRs <OPERATOR-NAME> merges; `claude/custody-declare` for PR #172; never any `main`, never force-push; on the homepage repo a PR that changes `index.html` carries the new hash and seal preimage and is never merged before its seal. Not covered: the witness repo (<WITNESS-HOST>'s), third-party repos (Mac, machine account, <OPERATOR-NAME>'s go). **Caveat learned 2026-09-05: a scheduled task's connector set is fixed at creation** — the two daily tasks created on 2026-08-22 never had this connector and could not have used this route; they were recreated (v2) with it on 2026-09-05. Check `list_triggers → mcp_connections` before assuming a task can reach a connector. **Caveat learned 2026-09-14: `push_files` records every blob `100644`.** Any executable pushed this route loses its mode — in `tests/` that is cosmetic, on the three shipped scripts it is the exit-126 regression of 2026-09-02. Either `chmod` and commit from the Mac behind the push, or do not send a shipped script this route at all (why: `notes/2026-09-14-connector-push-drops-the-exec-bit`) (rev. 2026-09-14).

**Why the container's own GitHub token 403s (settled 2026-09-05, not a token defect):** the git proxy injects credentials only for repositories declared as the session's sources, and Cowork sessions and scheduled tasks declare none — its exact refusal: *"<OPERATOR-FORK> is not in this session's authorized repository set, so the proxy will not inject a credential for it."* Routines at claude.ai/code have a repository step and would get proxied `git push` and `gh`; that is unprobed (migration sketch, step 1).

**Superseded paragraph (2026-09-03), kept for the record:** The 12:00 UTC scheduled run can now write to that fork directly through the GitHub connector (the "Claude Github MCP Connector" app, installed 2026-09-03 with Contents read & write), as <OPERATOR-GITHUB-LOGIN>: topic branches, or `claude/custody-declare` for PR #172; never `main`, never force-push. It does not cover the witness repo (<WITNESS-HOST>'s to write), the toolkit, or third-party repos, which keep the routes described below — Mac, machine account, human merge. Connector commits carry `9123721+<OPERATOR-GITHUB-LOGIN>@users.noreply.github.com`, not the commonwealth machine account, and any announcement of a change made this way must say so. Because `push_files` carries file contents rather than git objects, every connector push is verified by anonymous `git ls-remote` plus a per-file sha-256 against `raw.githubusercontent.com` before it counts as delivered. See `claude/1f916-docket-build.md` ENVIRONMENT item 6 (corrected) and the ledger row `queue/resource-github-write-path`.

**Authoritative for how code gets from a session to a branch.** The build doc's ENVIRONMENT section
records what was *tried*; `claude/1f916-probes.md` records what has *not* been; this file records
what to *do*. Written 2026-08-30 after the fourth delivery on `claude/custody-declare`, when the
process had been proven enough times to have a shape.

The short version: **a session queues, you carry and authorize, a session verifies.** How much you
carry depends on the route, and the difference is the whole reason to choose one: on **Route B** your
part really is one authorization, because the session reads the queued patch itself. On **Route A**
you are also the transport — the routine cannot read the project doc the patch is staged in, so it
has to be pasted into the routine's own prompt by hand. Everything else belongs to a session, and if
you find yourself doing more than that, something has gone wrong and the answer is probably in §7.

*(This file said "one decision and one authorization" for both routes when it was first written on
2026-08-30, which was wrong, and <OPERATOR-NAME> caught it within the hour by asking whether he had to update
the routine's description each time. A runbook that omits a step reads exactly as complete as one
that does not — the same defect this project has been chasing all week, in the document written to
prevent it.)*

---

## 0. What you are looking at when a patch is queued

**RETIRED AS A STAGING SURFACE, 2026-09-07 — §0, §1's Route A row and §2 record how Route A worked,
not what to do now.** `claude/1f916-fix-pusher-routine.md` was archived on 2026-09-02 and is now
`claude/archive/1f916-fix-pusher-routine.md`, where a changed archive is an incident; since
`queue/build-in-bridged-sittings` (2026-09-03) a session with a tested change and no route records
base, expected tree, file digests and resolution notes in a ledger `queue` row instead, and the
bridged sitting REBUILDS from those. Nothing is handed off as text. Kept rather than cut because the
reasoning below is still load-bearing: the two-hop problem is why that ledger row states a base and
an expected tree, and the tree assertion is still the mechanism on every route (§4).

A session that could not push wrote the patch into the **RUN BLOCK** of
`claude/archive/1f916-fix-pusher-routine.md` and said so. A non-empty RUN BLOCK meant *undelivered*.
It always states four things, and they are what make the handoff checkable rather than trusting:

- **base** — the commit the patch was built against
- **expected tree** — what the tree must be after applying, asserted *before* anything else runs
- **expected suite** — test counts and a clean `tsc`
- **task** — what changed and why

You do not need to read the patch. The tree hash is what catches a corrupted one, and it fails
loudly rather than quietly.

**But you do have to move it, and this is the step most easily missed.** `claude/1f916-probes.md` §3
settles it **from inside a routine run**, not by inference: a routine's tool inventory contains
nothing that reads Claude.ai Project knowledge — `ToolSearch` for the project tools returns
`No matching deferred tools found`, and the only "project" tools present belong to Todoist and
GitHub. **So a routine cannot read the queued patch.** The project doc is a staging area; the
routine's own saved prompt is where the patch has to actually be, and moving it there is manual.
Route B does not have this problem: a Cowork session *can* read project docs, which is how the block
is written in the first place.

*(An earlier draft justified this by saying a routine runs on the same substrate with less attached.
That premise is false — a routine's inventory is in several places **larger** than a scheduled Cowork
run's. The conclusion survived the probe; the reasoning did not. The three run types have different
surfaces, not nested ones, and none of them bounds another.)*

That gives the patch two hops on Route A — session → project doc → (you paste) → routine prompt →
applied — and it is exactly why the **expected tree** is stated and asserted before anything else
runs. The assertion is not ceremony; it is the only thing standing between a mis-paste and a branch
that looks fine.

**The hop is permanent for now.** The Artifact content channel that would have deleted it was probed
on 2026-08-30 and **failed**: a Claude Code session in an environment with Artifact content domains
added receives HTTP 403 from an artifact's content path, byte-identical to what an anonymous stranger
receives — the allowlist grants the host, not the content, because reads are per-artifact
token-authorized and a session holds no token (probes §1). So the tree assertion is not a stopgap
waiting to be replaced; it is the mechanism. **Route B avoids the hop entirely**, which is now its
structural advantage rather than a convenience.

*(Since 2026-09-03, `queue/build-in-bridged-sittings`: a scheduled run with a tested change and no
route records base, expected tree, file digests and resolution notes in a ledger `queue` row and
leaves the build to the bridged sitting, which REBUILDS from those. Nothing is ever handed off as
text — no bundle, patch or binary as base64 in a doc, a prompt or a transcript.)*

---

## 1. Your decision: which route

Three are proven. Pick on where you already are.

| route | your effort | when to use it |
|---|---|---|
| **A — fire the routine** *(retired 2026-09-07 — §0)* | **paste the RUN BLOCK into the routine's prompt**, check settings, fire — then nothing | you are not at the Mac, or you want it done unattended |
| **B — a bridged session** | approve one folder grant; the session builds, bundles and carries the result itself | you are already at the Mac with a session open — **the default since 2026-09-04** |
| **C — Claude Code on the web** | opens a session, drives it | fallback; how the branch was first pushed |

There is no quality difference in the result — all four commits on the branch were verified the same
way afterwards. B is what delivered `e34c6dd0` and `f875ae6a`; A delivered `8c61e2d6` and
`5aee0c12`.

**When a patch is already queued, B is materially less work for you and has one fewer place to go
wrong**, because the bridged session reads the RUN BLOCK out of the project doc itself instead of
you being the transport. A earns its place when nobody is at the Mac, or when the change is small
enough to describe in the prompt rather than paste as a patch.

---

## 2. Route A — fire the routine

At [claude.ai/code/routines](https://claude.ai/code/routines), open `custody-fix-pusher`.

1. **Paste the RUN BLOCK into the routine's prompt, replacing the previous one.** Open
   `claude/archive/1f916-fix-pusher-routine.md` (archived — see §0), copy the block under *"### 1. RUN BLOCK"* — task, base,
   expected tree, expected suite, and the patch between its fences — and put it in the same place in
   the routine's saved prompt. **The routine cannot fetch this for itself** (§0). Copy the whole
   block including the base and expected-tree lines: those are what make a mis-paste fail loudly
   instead of quietly, so a "just the patch" shortcut removes the only check on the step you just
   performed by hand.
2. **Check the connector list.** The form shows a **`Connectors`** tab with a count, listing each
   one by name, above a warning that Claude can use all of their tools *including writes* without
   asking during a run. Read that list and remove anything the run has no business touching.
   *(Corrected 2026-08-30: this step used to say the tab renders empty while silently inheriting
   everything, so the true set was visible only after Create under "Runs with." That was true when
   recorded on 2026-08-28 and is not true now — the count and the names are shown pre-Create. The
   step survives its justification: the set is still inherited at creation, still does not maintain
   itself, and the warning about unattended writes is worth reading every time.)*
3. Confirm **Auto-fix pull requests is OFF.** It only ever covers PRs the routine itself opened, so
   on #172 it does nothing — but it is the kind of setting that does something surprising later.
4. Confirm the network profile is **Custom allowed domains** and that the list still names
   `registry.npmjs.org` explicitly. The default Trusted-network profile does not include `1f916.ai`,
   and Custom does **not** include package managers unless a checkbox is ticked — so a routine can
   die on `npm ci` before any gate runs, in a way that looks like an environment fault rather than a
   setting.
5. **Schedule → Once**, a few minutes out. There is no manual-only trigger; Once is the controlled
   one-shot.
6. Fire it, and walk away. It clones, applies, asserts the tree, runs `npm ci` / `npm test` /
   `tsc`, pushes only on green, and reports.

**Do not accept its report as the outcome.** See §4.

## 3. Route B — a bridged session (the bundle route, adopted 2026-09-04)

With a Cowork session open on the Mac:

1. Tell it what to deliver — *"apply the fix-pusher RUN BLOCK to `claude/custody-declare`"*, or
   *"build the #8 fix-up and deliver it"*. A queued ledger row carries the rest.
2. **Approve the folder grants** when asked — `~/Projects` and `/tmp` (two folders at once is one
   prompt) (rev. 2026-09-17). On 2026-08-29, 2026-08-30 and 2026-09-04 this was your entire
   contribution to the push.
3. That is the end of your part.

What the session does, and what you should see it report, in this order:

- **Container.** Builds on a topic branch in a fresh clone of the current head (`git ls-remote`,
  never assumed), runs the suites with every log written outside the clone, reads the file list a
  reviewer will see (`git diff --stat <base>..HEAD`) before committing, commits with
  `git -c commit.gpgsign=false commit` — the container signs by default with a harness key registered
  to nobody (why: `notes/2026-09-13-container-auto-signs-commits`) — then `git bundle create
  <name>.bundle main..<branch>` and `git bundle verify`; records the branch **tip SHA**, **tree SHA**
  and `%G?` = `N` (rev. 2026-09-13).
- **Transfer.** `SendUserFile` → `device_commit_files` into the sitting's dated folder on the Mac
  (below), never into the clone; git fetches the bundle from there by path. It asserts the bundle's sha-256 on BOTH sides before anything reads it — a bridge
  write can report success without landing and an osascript call can report failure after
  succeeding (why: `notes/2026-09-08-device-commit-reported-a-write-that-did-not-land`) — and the
  integrity check is git's own object hashes: a corrupt bundle fails `git bundle verify` before
  anything is fetched. No base64, no gzip, no chunk hashes, nothing typed. `device_bash` makes no
  write in the clone: git runs on macOS proper, because the sandbox VM
  cannot unlink `.git/index.lock` and leaves it behind (why:
  `notes/lesson-2026-09-10-git-in-a-mounted-folder-cannot-clear-its-own-locks`) (rev. 2026-09-17).
  Every carry uses a file name no earlier carry in the sitting used, and the Mac asserts the expected
  sha-256 inside the same command that reads the file, aborting on a mismatch (why:
  `notes/2026-09-17-bridge-served-a-stale-file-after-overwrite`) (rev. 2026-09-17).
  Carried files (bundles, PR-body files, helper scripts), Mac-side logs and worktrees live under one
  folder per sitting, `/tmp/1f916-<YYYY-MM-DD>/` on the Mac, never loose in `~/Projects`; nothing
  carrying credential bytes goes there (why: `notes/2026-09-17-mac-temp-files-go-to-a-dated-tmp-folder`) (rev. 2026-09-17).
- **Mac.** One short osascript `do shell script` with no payload in it — the `device_bash` VM has
  git but no network and no `gh`, so fetch and push happen on macOS proper:
  `git fetch origin` (the bundle's prerequisites must be present) → `git bundle verify` →
  `git fetch <bundle> <branch>:<branch>` → **assert `git rev-parse <branch>^{tree}` equals the
  recorded tree, and `git log -1 --format=%G?` reads `N`** — `U` means the container's signer signed
  it and the commit is recreated unsigned in the container before anything goes further (rev.
  2026-09-13) → **RE-SIGN (since 2026-09-05; written here 2026-09-06 after being skipped once):**
  `git worktree add /tmp/1f916-<YYYY-MM-DD>/<repo>-wt <branch>` so the deployment clone stays on `main` throughout, then
  in the worktree `git rebase --exec 'git commit --amend --no-edit --reset-author -S' main` (why:
  `notes/2026-09-16-lesson-resign-must-reset-the-author`) (rev. 2026-09-17), then **assert the tree
  AGAIN** (it must be unchanged) and **expect the tip SHA to differ**; `git log -1 --format=%G?` must
  read `G`. Signing happens only when a commit object is CREATED on the Mac — a bundle carries the
  container's objects exactly, which is its virtue, so without this step the commit lands
  Unverified beside the operator's signed merges (homepage PR #2's `039568fa`, the specimen). First
  performed on toolkit PR #15 (`d94605c7` → `e3013b37`, tree `5c1527d1` either side); the key and
  git config are in `claude/1f916-signing-key-setup.md` → push with
  `GH_TOKEN=$(gh auth token --user commonwealth-1f916)` and a one-shot
  `credential.helper`, so the token is never argv and never printed → `gh api user --jq .login`
  read back as the account that token names, `commonwealth-1f916` (rev. 2026-09-17) → worktree
  removed, bundle deleted from the dated folder.
- **Verification (§4).** An anonymous `git ls-remote` and a fresh anonymous clone: the SHAs that
  landed are the SHAs that were built, **plus the one change the re-sign step makes**: a bundle
  carries the commit objects themselves, so the SHA that arrives on the Mac equals the one built in
  the container, and the re-sign then replaces it — on purpose, tree unchanged — with a signed one.
  So the tree is the invariant on every route; §4 says what the SHA is expected to do on each.
  **Which routes produce a signed commit, so no draft claims otherwise again:** only Route B with
  the re-sign step (author and committer `commonwealth-1f916`, `verified=true`). The GitHub
  connector — sittings and the scheduled runs, `push_files` — cannot sign and authors as <OPERATOR-GITHUB-LOGIN>'s
  noreply; container-built commits on Routes A and C are unsigned; GitHub-UI merges are signed by
  GitHub's web-flow key under whichever account clicked. Three commits pushed by the connector on
  2026-09-05 (`bc1526d3`, `08d78fc7`, `2bb54fbb`) read `unsigned` for exactly this reason and are not
  a skipped step (`queue/resign-step-not-applied-2026-09-05`, closed into `queue/runbook-resign-step`).
- **PR.** Opened from the Mac as the machine account with `gh pr create --body-file`, the body
  carried over the bridge as a file, never retyped. A comment posted the same way uses
  `gh api … -F body=@file` — **`-F`, not `-f`**: `-f` sends the literal text `@file`
  (2026-09-05, PATCHed within two minutes; `notes/2026-09-05-gh-api-f-does-not-read-files`).

It should never rely on the active `gh` account, never leave a persistent config change behind, and
never rewrite history — a fix-up to an open PR is a merge-from-main plus a commit, not a rebase.

---

## 4. The verification gate — never skip, never self-serve

**A session's own account of what it did is not evidence.** After any route, a session that had no
part in the push clones the fork fresh and reports head, tree, parent, author, committer and
diffstat. That is not your job, but it is your job to notice if it did not happen.

What a good verification looks like — this is `f875ae6a`, 2026-08-30:

    head    f875ae6a4b4bdd58da60caf751af9b982eb621a7
    tree    e6e25dc3e837334f75752cb276f9a0dec8071668   ← equals the queued expected tree
    parent  cba8d3cbb37246e2fd83bfefd58bd98e260d051d   ← equals the queued base, fast-forward
    author/committer  commonwealth noreply on both

**Expect the commit SHA to differ from the one the queueing session named** on Routes A and C. A
patch re-applied elsewhere reproduces the tree and not the commit. This has now happened three times
on this branch (`2127cf96`→`e34c6dd0`, `404969ce`→`cba8d3cb`, `5e34b7bc`→`f875ae6a`). **The tree
matching is the pass; the commit differing is normal.** On Route B (bundle) the SHA that arrives on
the Mac is expected to be identical to the container's, and — since the re-sign step of 2026-09-05
(§3) — the SHA that is *pushed* is expected to differ from it by exactly that step: same tree,
author and committer `commonwealth <321972176+commonwealth-1f916@users.noreply.github.com>` (the
re-sign resets both to the configured identity), `%G?` = `G`. An identical pushed SHA means the
re-sign was skipped; a different tree, or any other author or committer, is the finding (rev.
2026-09-17). On `<OPERATOR-FORK>` there is no re-sign step
and the pushed `%G?` is `N`; a `U` there is the container's signer and a finding (rev. 2026-09-13).
If the tree does *not* match, nothing else about the run matters — stop and say so.

---

## 5. What is never yours

Delegate these; doing them by hand is how the record drifts.

- **Verifying the push** — a session, from a clone it made itself.
- **Saying it on the board** — the pushing session opens a ledger `queue` row of tier `board-debt`
  (item, due, pointer); a check-in session files the comment and closes that row, its id in the
  `status` and a `closed_at` set. *(Corrected 2026-09-07: this said the debt goes in the build doc's
  `OWED ON THE BOARD` block, which the ledger replaced on 2026-09-02.)* On 2026-08-30 that loop
  closed on its own in 17 minutes. The time before, it took 35 and only
  because you asked a question.
- **Editing a PR body** — a bridged session, as the account that opened the PR (`<OPERATOR-GITHUB-LOGIN>` for
  #172, `commonwealth-1f916` for its own): read the current body unauthenticated, apply assert-once
  replacements to those exact bytes, `PATCH` with a token frozen and its login read back in the same
  command, then read the body back cache-busted and compare its sha-256 with the intended bytes. A
  push that moves a branch updates its PR body in the same sitting (rev. 2026-09-17).
- **Commenting on a PR as you** — a bridged session, as the account that opened the PR, from the Mac
  with a frozen token and `gh api … -F body=@file`, the body carried over the bridge as a file; the
  exact text is shown to you in the chat and posted only after your yes for that comment (rev.
  2026-09-17).
- **Closing the ledger row a delivery discharges** — the `queue` row and every sentence describing
  its state change, in the same edit, always. *(Before 2026-09-07 this read "emptying the RUN BLOCK
  and the ROUTINES sentence that describes it"; that surface is retired — §0.)*
- **Updating the record** — the ledger, as you go: one `runs` row per run or sitting, `queue` rows
  for what is still open, `notes` rows for anomalies and lessons. *(Corrected 2026-09-07: this named
  the build doc's handoff log and "the live Activity log at `claude/1f916-activity-log.md`". That log
  was retired as the record on 2026-09-02 and moved under `claude/archive/`; a session obeying the
  old text would have changed an archive, which the brief calls an incident.)*

## 6. What is irreducibly yours

Not because of policy, but because the surface will not accept anyone else.

- **Opening the cross-fork PR** — once per PR, browser.
- **Anything needing `gh auth` on the Mac**, and any GitHub account registration — ToS requires a
  human.

---

## 7. When it goes wrong, what it looks like

- **Tree mismatch after applying** → the patch did not arrive intact. Nothing else matters. Do not
  push; requeue.
- **`git bundle verify` fails, or "Repository lacks these prerequisite commits"** → the first is a
  corrupt transfer (re-commit the file; never retype anything); the second only means the Mac clone
  has not fetched `origin` yet — fetch and retry, it is not a bad bundle.
- **The routine re-applies a patch already on the branch, or reports the base does not match** → the
  RUN BLOCK in its saved prompt is the *previous* run's. That is the missed-paste signature, and it
  is why the block states a base: it fails at the base check rather than pushing something twice.
- **Red gate** → the run ends and pushes nothing. Correct behaviour. Read what failed.
- **`npm ci` fails before any test runs** → suspect the package-manager checkbox (§2.4), not the code.
- **Remote moved between apply and push** → the run must stop, not merge or rebase. #172's history is
  public testimony and strangers have cited its commits by SHA. Never `--force`, never `--no-verify`.
- **A push succeeds and the branch is right, but nothing appears on #1002** → the board-debt loop
  broke. Check the ledger `queue` for an open `board-debt` row; one still open past its `due` is the
  alarm and overrides the evening run's quiet-night gate.
- **The routine authors as the vendor default** → its prompt failed to set the four identity values.
  Fix the prompt, not the commit; #172's history is not rewritable.

## 8. Two standing cautions about the instruments

- **The GitHub MCP connector strips angle-bracketed text** from PR bodies and commit messages it
  returns (observed 2026-08-30 during the PR-body verification; an instrument claim — re-derive if
  the connector updates). Never diagnose a body from its output alone.
- **WebFetch caches 15 minutes per URL** (stated in the tool's own description; re-confirmed there
  2026-08-31 by the weekly audit). A verification fetch of a page you just changed can answer from
  before your change — this produced a false alarm on 2026-08-30 and was caught only by re-fetching
  with a distinct query string. **Always cache-bust a verification fetch.**

---

## Open, and deliberately not settled here

*(Pruned 2026-08-31 after the weekly audit's first sweep found this list contradicting the
document's own §0: the Artifact content channel and routine-project-doc access were still listed
here as open/inferred after both were settled on 2026-08-30 and recorded above. The tail lost the
edit. The settled items now live where they were settled — probes §1 and §3 — and only the genuinely
open ones remain.)*

- Whether a routine can **open** a PR (its "Auto-fix pull requests" setting implies yes; untested,
  and do not test it on #172).
- Whether the fix-pusher routine still holds the connector set it was created with. It is not
  self-maintaining and cannot be read from a session — only from the UI, which is why §2.2 is a step
  and not a note.
