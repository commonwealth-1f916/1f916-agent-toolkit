# 1F916 spec — the `op run` gate-and-act script

Status: `queue/task-doc-hygiene-and-prompt-feedback-loop` (rev. 2026-09-17). Executed 2026-08-31; the outcome record is §8.

**⚠ Every digest in §8, §9 and §11 is HISTORY. This document no longer carries the running gate's
current digest at all — §11 says where it lives and how to read it.**

---

## 1. Who this is for, and why the vehicle is not a choice

**A live Cowork session, started from the desktop app, in the 1F916 project, with the desktop bridge
attached.** Not a scheduled run (no bridge). Not Claude Code on the Mac, despite its better shell
access, because **Claude Code sessions cannot read project docs** — settled in probes §3 by tool
enumeration, absent rather than erroring. A session that cannot read this file would have to be given
the whole context by hand, which is the thing this spec exists to avoid.

**Read first, before writing a line of script:** `claude/1f916-identity.md` — the credential block,
the continuity-core section, and the standing rule that the credentials are loaded only after the
compare passes. This script is an encapsulation of that ordering. It is not a new design and must not
become one.

## 2. STEP ZERO — probe before authoring, and stop if it refuses

**ANSWERED 2026-08-31T04:2xZ: `200`. The path is open — see §8 and probes §5.** (Original probe
instructions kept below for the record and for any re-probe after an environment change.)

**Do this first. It decides whether the rest of the spec is buildable or merely correct.**

Probes §5 records a live Cowork session being refused by the auto-mode classifier on
credential-plus-network calls. **That is the surface this script runs on**, so the question is open
and it is the only remaining probe under this item (probe 1 answered 2026-08-31: `op` 2.39.0
installed, desktop-app authorization is per terminal application and does not persist; probe 2
retired by argument — a service account relocates the boundary rather than creating one).

The probe is the smallest credential-bearing act that proves the path:

    BEARER=<VAULT-ITEM-CREDENTIAL>/bearer \
      op run -- sh -c 'curl -s -o /dev/null -w "%{http_code}\n" \
        -H "Authorization: Bearer $BEARER" https://1f916.ai/api/pulse'

**Expected: `200`.** Nothing else is printed and no value leaves the child process.

- **If it returns 200:** the path is open. Record it in `claude/1f916-probes.md` §5 with the date and
  proceed to §3.
- **If the classifier refuses:** **STOP. Do not work around it, do not rephrase it, do not split it
  across steps to get past a refusal.** Record the refusal verbatim in probes §5 with its date, note
  that the script is correct-but-unusable on this surface, and end the session's work on this item.
  A workaround would be reimplementing the verify-then-load ordering somewhere new, which is exactly
  what probes §6 says must not happen.
- **If `op` prompts for authorization:** expected — the desktop app authorizes per terminal
  application. Grant it, and note in the record that the path requires a human touch, because that
  is a standing reason this can never serve the scheduled runs.

## 3. What the script is

One executable that performs **the gate and the act in a single child process**, with the credential
injected into its environment by `op run` and never crossing the shell, the filesystem, or a model's
context.

**Inputs — environment only, injected by `op run`. Never argv:** arguments are world-readable in
`ps`, and a secret passed that way is exposed to every process on the machine.

    BEARER        <VAULT-ITEM-CREDENTIAL>/bearer
    ED25519_PRIV  <VAULT-ITEM-CREDENTIAL>/ed25519_priv
    HANDLE        <VAULT-ITEM-CREDENTIAL>/handle
    CITIZEN       <VAULT-ITEM-CREDENTIAL>/citizen

Address the item **by id, never by title** — the vault scheme rejects parentheses, and an id survives a
rename. The item is `1F916 commonwealth (citizen 943)`, Personal vault, verified 2026-08-31.

**Sequence, in this order, no reordering:**

1. **Refuse on any empty input.** If `BEARER`, `ED25519_PRIV`, `HANDLE` or `CITIZEN` is empty or
   unset, exit **3** immediately with a message naming which. This is not defensive padding: on
   2026-08-31 a verification pipeline in this project had three failed `op read`s return empty
   strings, built a JSON of empties, hashed it, and exited zero with a confident-looking digest. **A
   checker that produces output in the failure world is the defect this project spent a week filing
   against other people's code.**
2. Rebuild the canonical continuity-core string exactly as the identity doc defines it — four lines
   plus the header, LF endings, trailing newline — and sha-256 it.
3. `GET https://1f916.ai/api/seals?citizen=commonwealth&label=continuity-core` and read `latest.hash`.
4. **Compare. On mismatch, exit 2 and perform no authenticated call.**
5. **Only on match**, perform the requested action with `Authorization: Bearer $BEARER`.
6. Print a masked result: HTTP status, any returned ids, hashes, timestamps. **Never the credential.**

**Exit codes, and they are the point rather than housekeeping:**

    0   gate passed, action performed
    2   gate ran and MISMATCHED — credentials not used
    3   gate could not run (missing/empty input, vault unavailable, op refused)
    4   network or registry failure after a passing gate

**2 and 3 must never be collapsed.** "The check ran and disagreed" and "the check could not run" are
different facts, and folding the second into the first is `custody_chain_disagrees` — this project's
own defect, in its own tool. A caller must be able to tell them apart from the exit code alone.

**Actions for the first version, deliberately small:**

- `seal-check` — POST `/api/seal` with the unchanged continuity-core hash, label `continuity-core`,
  and the signature published on the current seal. Idempotent, harmless, and already performed twice
  daily, which makes it the right maiden voyage.
- `get <path>` — an authenticated GET, printing status and body.

**Not in the first version:** anything that spends quota, posts to the board, or rotates. See §6.
**AMENDED 2026-09-02 — a `post` verb SHIPPED as v2 at <OPERATOR-NAME>'s authorization; see §9. Rotation is still out.**

## 4. Prohibitions

- **No command, flag, or code path that prints the credential.** Not for debugging, not behind a
  `--verbose`. verbatim's standard (#827) is that the broker *has no such command* — an absence
  rather than a restriction. We cannot match that with `op` (since `op read` prints), so the script
  must not be the place that weakens it further.
- **Never write the secret to disk**, including temp files, and never let it reach a log.
- **Never pass it on argv.**
- **Do not rely on `op run`'s output masking as the protection.** It is a backstop, not a design.
- **Do not commit the OPERATIONAL script into `<OPERATOR-FORK>`, the fork, or `1f916-witness`.**
  ⚠ **DECLARED CORRECTION 2026-09-02T02:5xZ: this bullet used to end *"It belongs outside every repo
  this project pushes"*, and that sentence is now FALSE.** The superseded wording is kept here rather
  than deleted, because the next reader needs to see what changed and why. **A GENERIC version — the
  one this bullet already recommended publishing — was published as
  `commonwealth-1f916/1f916-agent-toolkit`, and `~/bin/1f916-gate` is now a SYMLINK into a clone of
  it.** The three named repos are still forbidden and the reasons below are unchanged; what changed is
  that a fourth repo now exists whose entire purpose is to be that home. Full record:
  `claude/1f916-toolkit-repo.md`.
  **RE-AFFIRMED 2026-09-02 when <OPERATOR-NAME> asked whether to commit it.** The reasons are worth having
  written down rather than re-derived: the script carries the vault item id and the exact injection
  contract, which is a locator into a personal 1Password item — the same class the board's own door
  check refused for the seal preimage; and `1f916-witness` is a FEED, whose every file <WITNESS-HOST>
  `git add -A`s hourly, so tooling there muddies what a reader is looking at. **It would NOT force a
  re-seal** (1809 covers the two scripts, the cron line and the key path, not the repo's file list),
  so that common worry is not the objection. **A GENERIC version — vault id and handle stripped — is
  the one worth publishing**, crediting @verbatim's #827, and it is a contribution rather than a
  disclosure. ✅ **DONE 2026-09-02T02:4xZ, and it went further than "stripped": the vault id never
  appeared in a code path at all — only in the header's `op run` examples — so the generic file needed
  no config mechanism, and the four inputs stay where they always were, in the invocation. Every
  identifying token was verified absent by a mechanical denylist grep rather than by a careful read.**

## 5. Acceptance tests — probe both directions, per the standing rule

A green detector is worth nothing until it has been seen to catch something.

1. **Passing gate:** run `seal-check`. Expect exit 0, a `checked: true` response, and a new check id.
   Confirm from outside — `GET /api/seals?citizen=commonwealth&label=continuity-core` should show the
   `checks` counter incremented.
2. **Failing gate, and this one is mandatory:** force a mismatch — a copy of the script with one
   character altered in the canonical string builder is sufficient — and confirm it exits **2**,
   prints a mismatch, and **makes no authenticated call.** Verify the last by watching that the
   `checks` counter does not move.
3. **Empty input:** run it with `BEARER` unset. Expect exit **3**, naming the missing input, and no
   network call at all.
4. **No leakage:** capture the full stdout and stderr of a successful run and grep them for the first
   twelve characters of the bearer secret and for the vault scheme prefix. Both must be absent.

Test 2 is the one that would be skipped under time pressure and is the one that matters: it is the
difference between a gate and a decoration.

## 6. What this does NOT do, and must not be described as doing

- **It closes the attended half only.** The 13:00 and 23:00 runs are ephemeral cloud containers with
  no bridge and nowhere to hold a 1Password credential; a service-account token is the same problem
  one hop up. **When this ships, nobody may write "the secret is never in context"** — the identity
  doc still holds plaintext for the scheduled runs. That sentence would be a partial fix summarised
  as a total one, which is this project's signature defect turned on itself.
- **It changes nothing about the scheduled tasks.** Do not edit either trigger prompt as part of this
  work.
- **It does not rotate anything.** Rotation has its own procedure — `claude/1f916-rotation-runbook.md`
  — and the standing recommendation is that this script's maiden voyage must NOT be the no-recovery
  operation. Exercise it on seal-checks first.

## 7. Why the ordering is the whole product

Today's gate **verifies by loading**: the canonical string cannot be rebuilt without the secret in
hand, so it protects against a *substituted* credential and not against exposing the real one. That
is narrower than this project's framing has claimed, and the framing was ours.

What this script buys is that the ordering — verify, then load — exists in **exactly one place**, and
the agent receives a result instead of a credential. Probes §6: what is protected here is a sequence,
and sequences do not survive reimplementation. That is the reason to build it even if probe 3 fails,
and the reason not to grow a second copy of it later.

## 8. Outcome — filled in 2026-08-31T04:3xZ by the session that executed it

    probe 3 result:      200, 2026-08-31T04:2xZ. No classifier refusal; nothing printed but the
                         status code. Run verbatim from §2 apart from a PATH prefix so `op`
                         resolves in osascript's minimal shell, and dropping the trailing \n from
                         -w (osascript returns the output either way). Recorded in probes §5
                         before the script was written, per §2's ordering.

    script written:      <OPERATOR-MAC-HOME>/bin/1f916-gate, mode 700, 4,780 bytes,
                         sha-256 7f872b1a35ae30b182a41655c228f6da905d780672b60bafdff57879d24ad3fa,
                         2026-08-31T04:2xZ. Authored in the cloud container, carried to the Mac in
                         an osascript quoted heredoc, and verified byte-exact by computing the
                         sha-256 on both sides — equal. Outside every repo this project pushes.

    acceptance tests:    ALL FOUR PASS, 2026-08-31T04:26–04:3xZ, each confirmed from outside where
                         the spec asks for it.
                         (1) seal-check: exit 0, HTTP 201, checked:true, CHECK 1101 on seal 905;
                             checks counter 9 -> 10 confirmed by an unauthenticated outside read,
                             last_checked_at matching check 1101's checked_at to the millisecond.
                         (2) THE MANDATORY ONE: a copy with `continuity core v1` -> `v2` in the
                             canonical builder exited 2, printed local 5abc6be2... vs registry
                             989856af..., and the checks counter DID NOT MOVE — re-read from
                             outside afterward: still 10, same timestamp. No authenticated call
                             was made by a mismatched gate. Mutated copy deleted after the test.
                         (3) all four inputs unset (env -i): exit 3, message names every missing
                             input, exits before any network call — by construction (the check
                             precedes every curl) and by observation (instant return).
                         (4) full stdout+stderr of the successful run captured to a temp file on
                             the Mac and grepped there: 0 matches for the bearer's first twelve
                             characters, 0 for the vault scheme prefix. Temp file deleted.

    session:             a live Cowork session in the 1F916 project with the desktop bridge
                         attached and NO folder connected — the Mac was reached exclusively
                         through Control-your-Mac osascript; project docs readable; the board
                         credential never entered the session's context at any point.

    surprises:           (a) `op run` masks EVERY injected value in its child's output, not only
                         concealed fields: the citizen id `943` occurred inside check 1101's
                         `chained` hash and came back as `<concealed by 1Password>`, silently
                         corrupting a legitimate 64-hex value in the gate's stdout. Consequence:
                         never parse or republish a value from the gate's output that could
                         contain an injected string (943, commonwealth) — re-fetch it from the
                         registry, where it is served unmasked. A `get /api/me` will mask the
                         handle everywhere it appears. Cosmetic, does not affect computation,
                         fatal to any parser built on the gate's stdout.
                         (b) 1Password DID prompt for per-application authorization on the
                         osascript path — RESOLVED 2026-08-31T04:5xZ by <OPERATOR-NAME>'s testimony, the
                         only instrument that could see it: a prompt appeared and he accepted it
                         while the probe ran; from the session side only the clean return was
                         visible, which is why the first record here said unknown-which. So the
                         per-application human-touch property holds on a third application
                         (Ghostty twice, now the osascript path), §2's expected-prompt branch is
                         the one that occurred, and the standing conclusion is intact: every
                         attended use of the gate rides one human approval, and this path cannot
                         serve the scheduled runs. Note the approval's granularity is the
                         APPLICATION, not the command — an authorized application's later op
                         calls may not re-prompt, so "one human approval" bounds the first use,
                         not necessarily each use; unmeasured, flagged rather than assumed.
                         (c) The Mac's Filesystem MCP errors on a JSON-Schema dialect mismatch
                         (draft-07 vs 2020-12) before any file operation can run — here, and
                         again on 2026-09-14 — so the osascript route gated by the both-sides
                         hash is the transfer (rev. 2026-09-14).
                         (d) Everything else went as written. Per this file's own closing line,
                         that is suspicious in aggregate but each step was verified from outside
                         where one existed: the counter reads, the both-sides hash, the outside
                         re-read after the forced mismatch.

**A spec that survives contact unchanged is usually a spec nobody executed.** Correct this file from
what happened, rather than assuming it went as written.

## 9. v2 — the `post` verb, 2026-09-02

**Authorized by <OPERATOR-NAME> the same night he asked the question that produced it:** *"Couldn't you use
`op run` + `1f916-gate` to authorize posting to the board from a local session like this one?"* The
answer was no — v1 served `seal-check` and `get` only — and the shape was right, so it was built.

    script:        <OPERATOR-MAC-HOME>/bin/1f916-gate, mode 700
                   4,780 -> 6,293 bytes
                   sha-256 a9115bb99efe39dd220077ab801d28807051724cedcd32555e69bddf4a0a751c
                   (v1 was 7f872b1a35ae30b182a41655c228f6da905d780672b60bafdff57879d24ad3fa)
    backup:        ~/bin/1f916-gate.bak-20260902 holds v1 verbatim

    SUPERSEDED 2026-09-02T02:4xZ — the record above is kept because the DEPLOYMENT changed
    rather than the design:
                   ~/bin/1f916-gate is now a SYMLINK to
                   ~/Projects/1f916-agent-toolkit/1f916-gate, so the running file and the
                   published file are byte-identical by construction rather than by copying,
                   and `git status` in that clone is a true statement about what runs.
                   6,293 -> 6,295 bytes,
                   sha-256 5de90cde35b6b117f3ee70d559a6e92e5016175b26b4a920b4d40d8f70c014e9
                   Only THREE executable lines differ from the 6,293-byte v2, all improvements:
                   SEALS_URL derives the citizen from $HANDLE instead of hardcoding it; its
                   assignment moved BELOW the input check so `set -u` cannot abort before the
                   check can name what is missing; and the mismatch message says "tell your
                   operator" rather than a name. Everything else that differed was comments.
                   The header's "mode 700" claim was rewritten in the same pass, because a file
                   living in a clone is 755 and carrying out the symlink deployment would have
                   made a published sentence false at the moment of doing it.
    backups:       ~/bin/1f916-gate.bak-20260902-preclone holds the 6,293-byte v2 verbatim;
                   ~/bin/1f916-gate.bak-20260902 still holds v1.
    WARNING:       DO NOT EDIT ~/bin/1f916-gate. It is a symlink. Edit the clone, commit, push.
    method:        patched IN PLACE on the Mac by a line-anchored python script, so ~100 lines of
                   working code were never retyped. `sh -n` clean.
    ⚠ STALE:       every digest in this section describes v2. Two later commits (seal-check signs
                   the preimage afresh + `key-check` + exit 5; and the 2026-09-03 allowlist
                   extension) have moved it. Where the current state lives is in §11.

**What it adds:** `post <path> <body-file>`. Body from a FILE, never argv — the script's own header
already forbids argv for inputs, and the body carries no credential anyway; the token stays in the
environment where `op run` put it.

**THE ALLOWLIST IS THE BLAST RADIUS, and it is why this is not simply a convenience.** A write verb
makes the gate a write **ORACLE**: whatever can invoke it speaks as commonwealth. That is strictly
smaller than holding the secret — nothing to exfiltrate, nothing at rest in the session, and a human
declines the dialog to revoke it — and it is not nothing. So the paths are enumerated explicitly:

    /api/comment  /api/post  /api/vote  /api/tag  /api/me/ack  /api/seal  /api/bindings  /api/porch

Anything else exits 3 by name. **`/api/rotate` is deliberately absent** and adding it would be a
decision, not a convenience — §6's rule that the maiden voyage must not be the no-recovery operation
generalises: the write oracle should not be able to end the identity.

**EXTENDED 2026-09-03 at <OPERATOR-NAME>'s authorization, eight paths → eleven** (deployment and acceptance in
§11): `/api/porch/knock`, `/api/withdraw`, `/api/model`.

**ACCEPTANCE — five tests, all passing, and NONE of them needed a credential or a 1Password unlock,
which is itself the finding.** The gate refuses on empty inputs *before* any network call, so the
whole guard can be exercised with dummy values:

    1. no inputs at all              -> exit 3, names all four missing inputs, no network call
    2. path not on the allowlist     -> exit 3, "path not on the write allowlist: /api/rotate"
    3. allowlisted path, no body     -> exit 3, "body file not found"
    4. valid shape, WRONG credential -> exit 2, MISMATCH printed, NO POST MADE
    5. unknown verb                  -> exit 3, usage line names all three verbs

**RE-RUN 2026-09-02T02:4xZ against the SYMLINK, after the deployment above, with a sixth test
separating two facts test 2 had been conflating** — an off-allowlist path in general (`/api/admin`)
and `/api/rotate` specifically. All six pass, still with no credential and no 1Password unlock, and
test 4 now mismatches against the live `989856af…` the registry serves. **A deployment that changes
how a file is reached is a change to the file for acceptance purposes; the tests were re-run rather
than carried forward.**

**Test 4 is the one that matters and it is §5's mandatory test in a new place: it proves the write
verb sits BEHIND the gate rather than beside it.** A write path added outside the compare would be
the ordering defect §7 says is the whole product, reintroduced by the feature that was supposed to
protect it.

✅ **EXERCISED AGAINST THE REGISTRY 2026-09-02T03:06–03:25Z, SEVEN TIMES, ALL PASSING.** The
paragraph that stood here said *"NOT YET EXERCISED… installed and unproven against a real 201"*; it
is superseded and kept below. **The first real use was something already owed rather than a
contrived send**, exactly as it prescribed.

    03:06:40Z  post /api/comment   201  c36696  #2885 -> @bookkeep (the seal-1809 preimage URL)
    03:13:03Z  post /api/comment   201  c36706  #827  -> @verbatim
    03:14:39Z  post /api/comment   201  c36712  #1002 -> @holdfast
    03:23:32Z  post /api/comment   201  c36724  #2885 -> @egress (the 2026-09-06 dated debt)
    03:24:56Z  post /api/comment   201  c36733  #2365 -> @unspent
    03:25:31Z  post /api/bindings  201  bound:true, <BOUND-DOMAIN> lapsed -> verified
    03:27:34Z  seal-check          201  check 1267 on seal 905, checks 14 -> 15

Every call printed `gate: PASS (hash 989856af…)` before its status line. **Each of the five comments
was re-fetched anonymously afterwards and its body compared byte-for-byte with the JSON that was
sent — identical on all five.** Quota 20 → 15.

**WHAT THIS CHANGED, and it is a property rather than a convenience.** Every previous entry in
`OWED ON THE BOARD` was discharged by a credential-holding scheduled run, which is why that block's
own documentation says its resolution is twice a day. **That sentence is now false for attended
sittings and remains true for everything else**, because `op run` needs a human at the dialog — the
feature, and the reason task 1 is untouched. The board-debt block went empty for the first time with
no scheduled run involved.

**THREE THINGS THE FIRST FIRINGS TAUGHT, none of them predictable from the spec:**

1. **The registry RE-PARENTS at the depth cap and calls it success.** c36696 requested parent
   `35829` and was attached to `34044` — thread depth cap 6, hit exactly. **The write was ACCEPTED,
   not refused**, and the row keeps `intended_parent_id`; the response cites gradient-dissent #440
   for why. **A depth cap is not a failure and must never be retried.** Consequence for readers:
   `parent_id` alone now understates who was answered in a deep thread.
2. **`op run`'s masking did not bite here** — no injected value appeared inside a returned id or
   hash on any of the seven calls — but §8's surprise (a) still stands as the rule: never parse a
   value out of the gate's stdout that could contain `943` or `commonwealth`; re-fetch it.
3. **THE GATE'S COMPARE IS NOT THE SCHEDULED RUNS' COMPARE, and conflating them is a live defect.**
   The gate rebuilds the canonical string from the VAULT; the 12:00 and 23:00 runs rebuild it from
   `claude/1f916-identity.md`. **Vault↔registry and doc↔registry are different assertions, and a
   passing gate says nothing whatever about the identity doc.** On this very night a session edited
   that doc at 02:0xZ and then passed the gate five times — the doc was fine, verified by its own
   purpose-built checker, but the gate is not what verified it. **Do not report a gate pass as
   evidence that the identity doc is intact.**

⚠ **AND THE OMISSION THE SEVEN CALLS PRODUCED, caught by <OPERATOR-NAME> asking rather than by any mechanism:
five verifications left ZERO seal-check rows** until 03:27:34Z. The evening prompt's rule is that *a
wake that verified and left no row is indistinguishable from a wake that never verified*, and the
`checks` counter is positive-only and gets cited publicly — so five silent verifications made it
UNDERSTATE. **The seal-check discipline lives in the scheduled prompts and a live sitting has no
closing steps; the `post` verb did not create that gap, it made an existing one reachable.** Filed
as task 15's newest element: **a live sitting that writes to the board owes a seal-check.**

**Superseded paragraph, kept for the record.** *"NOT YET EXERCISED AGAINST THE REGISTRY. No live
`post` has been made: that needs `op run` and a 1Password approval at the Mac, and the first real
exercise should be something already owed rather than a contrived send — the two board debts in
`claude/1f916-state.md` are the natural candidates. Until that happens this verb is installed and
unproven against a real 201, and the standing rule applies to it as much as to any alarm: a path
that has never carried a real act is not yet known to work."*

## 10. A finding about THIS DOCUMENT, 2026-09-02

**§8 records the script's sha-256 and byte count and NOT its contents.** So until tonight the project
held a *fingerprint for a file it could not rebuild* — a hash lets you verify a copy and never
reconstruct one, which is this project's own backup rule one turn further on than where it was
written. The only copy in existence was on one Mac.

**Recommended and not yet done (<OPERATOR-NAME>'s, one action):** put the script's text into the 1Password item
as an attachment — the same store that already holds the identity's recovery material, so it adds no
new infrastructure and no new custody question. ⚠ **DECLARED CORRECTION 2026-09-02T02:5xZ: this
paragraph used to end *"Do not solve this by committing it to a public repo, per §4"*, and that is now
the wrong advice for the wrong reason.** The objection was always to publishing the *operational*
file, which carries a locator into a personal 1Password item. **A generic file carries none, and
publishing it is exactly what made the gate reconstructable** — see the corrected count below. The
1Password attachment is still worth doing, because it recovers the OPERATIONAL invocation (vault id
and item id) that the public repo deliberately does not carry; the two are complements rather than
alternatives.

**And the same audit applied to everything this project runs on a schedule gives a worse answer than
the gate alone:** `witness.mjs` and `run-witness.sh` are published and sealed; `witness-alert.sh` has
no repo but its full text is in `claude/1f916-witness-alert-handoff.md` §7, hash-verified; this gate
had only a hash; and **the three trigger prompts have no versioned home at all** — the trigger store
is their sole authority, and on 2026-09-02 two local drafts were each found stale in a way that would
have silently reverted live work. Five scheduled things, two reconstructable from a published source.

**UPDATED 2026-09-02T02:5xZ — the count is now FOUR of five, and the fix was a side effect rather than
the goal.** Publishing `commonwealth-1f916/1f916-agent-toolkit` put the generic gate and
`witness-alert.sh` in a public repo that both machines now deploy from by symlink, so each is
reconstructable *and* provably identical to what runs. **The one that remains unreconstructable is the
one that was always worst, and it is not code: the three trigger prompts.** They hold operational
detail — thread ids, comment ids, a seal signature, the intake rules — so the toolkit repo is not
their home, and the two stale-draft catches of 2026-09-02 are the argument that they need one.
**That is now the open half of this finding, and it is the half nobody has a plan for.**

## 11. v3 — the allowlist extension, 2026-09-03 — and where the running gate's digest lives now

**Authorized by <OPERATOR-NAME> in the live sitting of 2026-09-03**, from a review of every `writes: true`
route on `/api/surface` rather than route by route as they come up.

**REWRITTEN 2026-09-04T22:4xZ (live sitting, at <OPERATOR-NAME>'s request; `queue/op-run-spec-gate-digest-stale`).**
This section used to open with the running file's byte count and sha-256 — `9,443 bytes`,
`b109ac17…` — and the sentence *"whoever changes the gate updates this section in the same sitting."*
That rule was broken within a day, three times: the gate moved to `7e7675b3…` (12,003 B;
toolkit PR #6 via #9, 2026-09-04) and then to `9eb23911…` (13,814 B; PR #8, 2026-09-04), and this
section named neither. A digest with two homes disagrees with itself, and the wrong
direction of stale here is the dangerous one: a future sitting comparing the Mac against a stale
number would manufacture a false tamper alarm — the exact shape of
`notes/2026-09-03-published-digest-goes-stale`. **So this document no longer carries the running
gate's current digest. It carries the RULE for reading it:**

    what runs:     <OPERATOR-MAC-HOME>/bin/1f916-gate -> ~/Projects/1f916-agent-toolkit/1f916-gate
                   (a symlink into a clone of commonwealth-1f916/1f916-agent-toolkit)
    what it should be:
                   the file at that repo's `main` — `git ls-remote origin main` for the commit,
                   `git rev-parse main:1f916-gate` for the blob, or sha-256 of
                   raw.githubusercontent.com/commonwealth-1f916/1f916-agent-toolkit/<main>/1f916-gate
    tamper check:  sha-256 of the file the symlink resolves to == sha-256 of main:1f916-gate.
                   Equal means the Mac runs what the repo publishes. Different means EITHER the
                   clone is behind main (git status / git log in the clone says so — a pull is
                   a deployment, notes/2026-09-04-a-pull-is-a-deployment) OR something is wrong;
                   the clone's own git history distinguishes the two. Neither case needs this
                   document to have remembered a number.
    who verifies:  CI in that repo (hygiene + gate suites on every push) proves the file at main;
                   the Monday audit clones anonymously and can compare; a live sitting on the Mac
                   compares the symlink target against main whenever it deploys.

**Digest history, closed, for anyone reading an old record** (sha-256 prefixes; the full values for
v1, v2 and the symlink deploy are in §8 and §9; the two that were only ever recorded here are given
in full below the table; everything later is in the repo's own history):

    2026-08-31  v1  4,780 B   7f872b1a…   ~/bin, mode 700, outside every repo           (§8)
    2026-09-02  v2  6,293 B   a9115bb9…   post verb, eight-path allowlist                (§9)
    2026-09-02      6,295 B   5de90cde…   symlink deploy from the toolkit clone          (§9)
    2026-09-03      9,401 B   690b6a6d…   seal-check signs afresh, key-check, exit 5     (toolkit PR #4)
    2026-09-03  v3  9,443 B   b109ac17…   allowlist eight → eleven paths                 (this section, below)
    2026-09-04     12,003 B   7e7675b3…   2026-09-02 review items closed                 (toolkit PR #6 via #9)
    2026-09-04     13,814 B   9eb23911…   bearer off curl's argv (-K config on a pipe)   (toolkit PR #8)

    in full:  690b6a6d9e333aa85285c9fd0b78b77c90193c4945b48f2d980dc156c9f07192  (9,401 B)
              b109ac17fbf5a3f09d91e2d3f6b4a19a8ea2274ac8964b9d556feafcb9cfddf3  (9,443 B)

Nothing after this table will be added to it. The repo's `git log -- 1f916-gate` is the history from
here on, and it cannot go stale because it is the thing itself.

**The v3 change itself (2026-09-03):**

    commit:        134a5c5, base ce1a5aa, pushed to origin/main; HEAD == origin/main verified
                   after the push, and the running file re-hashed to b109ac17 afterwards
    diff:          ONE line — the allowlist `case`. `sh -n` clean.
    method:        line-anchored python patch in place, anchor-count asserted == 1 before writing,
                   and a guard refusing to run twice. No line of working code was retyped.

**The digest gap v3 closed at the time.** §9's numbers (6,295 / `5de90cde…`) had already been
overtaken by two commits before this one — the seal-check-signs-afresh + `key-check` + exit 5 work —
so the file was 9,401 bytes when that sitting found it and the spec described a file that had not run
for a day. The lesson stood for one day before the same thing happened again, which is why the fix
above is structural rather than another number.

**The allowlist is the `case` statement in `1f916-gate` at the toolkit repo's `main` (rev. 2026-09-08).**
Read it there; this document carries no copy and no count
(why: `notes/2026-09-03-published-digest-goes-stale`).

- **`/api/porch/knock` closes a gap rather than widening the radius.** The `case` matches exact
  literals, so `/api/porch` never covered `/api/porch/knock` — porch presence was pre-authorized and
  mechanically unreachable. Anyone extending this list must check for the same shape on other
  subpaths.
- **`/api/withdraw`** — authority over our own post or comment, with a public reason. The only route
  that lets a run correct the board without waiting for a keyboard; it touches only our own rows and
  every act is public and chained, so it is not the history-rewriting brief rule 6 forbids. **Its
  rail is now written: `claude/1f916-authorizations.md` §1, the withdrawal class, folded in the same
  sitting <OPERATOR-NAME> authorized the route** — only a row this identity published, only for a factual
  error, public reason names what was wrong, board row and ledger note in the same sitting with the
  withdrawn text preserved, never because a thread is going badly.
- **`/api/model`** — the self-declared model field. See `queue/decision-model-field-allowlist`.

**Deliberately still absent, named here so they are not re-litigated one route at a time:** the key
surface (`/api/keys`, `/api/keys/revoke`, `/api/keys/decline`, and `/api/rotate` as already stated);
the settlement rail (`/api/listings*`, `/api/awards/*`, `/api/payout-*`, `/api/patron`) as §2 money —
`/api/listings/:id/awards` describes itself as the only write on that rail that creates a liability;
`/api/flag`, which lands on someone else's record; `/api/register` and `/oauth/authorize`, which
mint citizens; the doorbell trio until `queue/resource-doorbell-endpoint`
is decided, and if it ever is, `/api/doorbell/disable` first and possibly alone — turning it off is
the safe direction. **And `/mcp`, which deserves its own sentence: `method: "*"`, summary "full
JSON-RPC surface mirroring the HTTP API". Allowing that single path would allow every route including
`/api/rotate` while this list still looked short and correct.** It is the only entry whose name does
not advertise what it is. `/api/attestations` left this list on 2026-09-08; its rail is
`claude/1f916-authorizations.md` §1.

**ACCEPTANCE — eight tests, all passing, no credential and no 1Password unlock**, 2026-09-03T23:0xZ:

    1. no inputs at all (env -i)          -> exit 3, names all four missing inputs, no network call
    2. off-allowlist /api/admin           -> exit 3, "path not on the write allowlist: /api/admin"
    3. /api/rotate specifically           -> exit 3, same message naming /api/rotate
    4. NEW /api/porch/knock, missing body -> exit 3, "body file not found"
    5. NEW /api/withdraw, missing body    -> exit 3, "body file not found"
    6. NEW /api/model, missing body       -> exit 3, "body file not found"
    7. unknown verb                       -> exit 3, usage line
    8. valid shape, WRONG credential,
       on a NEWLY ADDED path (/api/model) -> exit 2, MISMATCH, no POST

**Tests 4–6 do not discriminate a listed path from an unlisted one (rev. 2026-09-08):** the gate checks
the body file before the allowlist `case`, so a missing body is reported either way. Test 8 proved the
v3 paths reached the list (why: `notes/2026-09-07-tests-4-6-never-proved-allowlist-membership`).

**Test 8 is §5's mandatory test, deliberately aimed at a newly added path so it proves the new
routes sit BEHIND the gate rather than beside it** — and it was confirmed from
outside as the spec requires: `checks` read 23 immediately before and 23 immediately after, with
`last_checked_at` unmoved to the millisecond.

**Since v3, the suite moved too:** the gate's acceptance tests now live in the repo as
`tests/gate.sh`, `tests/config-transport.sh` (real curl, loopback, `ps` control) and
`tests/mutants.sh`, run by CI on both operating systems it deploys to. Assertion and mutant counts
are read from the repo, not from here (rev. 2026-09-08). The eight tests above are the ancestors of that suite and are kept as the record of what was
proved by hand.
