# 1F916 runbook — rotating the bearer secret

Status: `queue/rotate-bearer` (rev. 2026-11-03).

No rotation has been run, so this document is a design, not a record. Every step below that has not been executed is marked. When the first
rotation happens, correct this file from what actually occurred rather than assuming it went as
written — that correction is the most valuable thing the first run produces.

Written 2026-08-31 by the 23:00 scheduled run, at <OPERATOR-NAME>'s request, after he asked how often the
secret should be rotated. Authoritative for the *procedure*; `claude/1f916-identity.md` stays
authoritative for the seal facts (the credential values are only in the vault since 2026-11-13), and this file deliberately duplicates
neither.

---

## 1. The one thing that can actually go wrong

**Losing the new secret is the only unrecoverable outcome. Everything else in this procedure fails
closed.**

`POST /api/rotate` requires the current secret and there is no recovery. If the call succeeds and
the new value is not captured somewhere durable in the same breath, commonwealth is gone — the
identity, the docket claim, witness #6's registration pointer, the seals, the karma, all of it. No
appeal, no support channel, nothing on the board can restore it.

Losing the secret no longer strands the bound Ed25519 key. `GET /api/surface`, read 2026-10-19, serves `POST /api/keys/revoke` with auth optional: a request with no bearer that carries the key's own signature over `1f916.key-revoke.v1:<handle>:<thumbprint>` revokes it (revoke-key-only). The same reading means whoever holds the private key can revoke it with no bearer, so the private key is a revocation credential and is held as carefully as the secret.

By contrast, **every partial state of the rest of the procedure is safe**, and this is worth
internalising before starting because it removes the temptation to hurry:

- New seal filed, vault not yet updated → the vault copy's hash no longer matches `latest`
  → the next run's gate **fails closed**, refuses its own credentials, and reports possible
  tampering to <OPERATOR-NAME>.
- Vault updated, new seal not yet filed → same mismatch, same fail-closed, same report (rev. 2026-11-13:
  the gate is built from the vault; the identity doc holds no credential).
- Both done, a trigger prompt still naming the old seal → the seal-*check* step misbehaves or is
  refused; no credential is exposed and no board write is corrupted.

**There is no ordering of the doc and the seal that fails open.** So the sequencing below is
optimised entirely around never losing the value, and only secondarily around minimising the window
in which a run would alarm.

## 2. What rotation does and does not touch

| touched | not touched |
|---|---|
| The bearer secret | The **Ed25519 keypair**, unaffected here. `POST /api/rotate` swaps the bearer only. The key has its own two routes (surface read 2026-10-19): `POST /api/keys/rotate` (bearer, plus old and new key both signing one dated payload; one chained key-rotate event) and `POST /api/keys/revoke` (§1) |
| The continuity-core canonical string (the secret is one of its five lines) | Seal **1809** `witness-reference` — its string names no secret; **do not re-seal it** |
| Seal **905**'s label `continuity-core` — a new hash under the same label records a **new seal**, not a check | Witness #6's registration, pointer URL, key, or feed |
| The identity doc's Expected-hash line and seal facts (it holds no credential lines since 2026-11-13) | The docket row, PR #172, the fork, the machine account |
| **Both daily trigger prompts** — see §4, this is the easy one to miss | Karma, claims, attestations, domain binding |
| **`~/bin/1f916-gate` needs NO edit** — it reads the vault and the live seals endpoint, so it follows a rotation automatically — but the **1Password item's `bearer` field is a holder and must be updated in §5 step 4** | |

Because the Ed25519 key is untouched, the new continuity-core seal is signed with the **same** key
as seal 905, and every prior signed check remains valid testimony about the interval it covered.

## 3. The contract is undocumented — plan for both shapes

`GET /api/surface` describes the route in exactly one sentence:

> `POST /api/rotate` — auth: bearer — *"Swap your key. Requires the current one; there is no
> recovery."*

**It documents no request body and no response shape.** Read 2026-08-31T02:5xZ. So it is not known
from outside whether the registry **mints** a new secret and returns it, or **accepts** one the
caller proposes. Nobody here has called it, and it cannot be rehearsed against a scratch identity —
there isn't one.

**The procedure below is written to be safe under either shape**, which is the only responsible way
to write it:

- If the registry **mints and returns**: the response body contains the only copy of the new value
  in existence. Capturing it is the whole ballgame (§5, step 4).
- If the registry **accepts a proposed value**: generate it locally with a CSPRNG, write it to
  1Password *before* the call, and the call is then merely a switch-over.

**Step 3 of §5 exists to settle this without risking anything**, and it must not be skipped.

## 4. Every place the value lives — enumerate before touching anything

Rotation is only as complete as this list, and the list is checked at rotation time rather than
trusted from this document.

**Holders — corrected twice on 2026-08-31. The original version of this section was headed "Verified
holders" and listed 1Password on a nine-day-old verbal report with a read time borrowed from an
unrelated check; the first correction then over-shot and declared the project doc the sole copy,
inferring absence-from-all-stores from absence-from-one. Both are left visible: this is the section
of a custody document that enumerates custody, and it got custody wrong twice in one night.**

1. **`claude/1f916-identity.md`** — no longer a holder: the operator took the credential lines out on
   2026-11-13 (the archive copy was made from the operator's export without them). Until then it was the plaintext
   copy every wake read.
2. **1Password — VERIFIED 2026-08-31T03:4xZ**, Secure Note `1F916 commonwealth (citizen 943)`,
   Personal vault, **`<VAULT-ITEM-CREDENTIAL>`** (address it by **id**, never by
   title: the vault scheme rejects parentheses and an id survives a rename). Checked by reading `handle`,
   `citizen`, `bearer`, `ed25519_priv` out of the vault and hashing them to **989856af…** — seal 905
   exactly, so all four are byte-exact and this copy alone can pass the wake gate. Reads are behind
   an interactive desktop-app unlock, per terminal application. **Since 2026-08-31 this copy is
   load-bearing, not just backup: `~/bin/1f916-gate` reads it via `op run` for every attended
   authenticated act.**
3. **A second, independent backup** — <OPERATOR-NAME>'s testimony, 2026-08-31, not 1Password, **not verified.**
   Carry it in that register; do not upgrade it by repetition, which is how the 2026-08-22 sentence
   survived nine days. Keep it: two independent copies beat one. Before any rotation, <OPERATOR-NAME> confirms
   where it lives and that it can be written quickly (rev. 2026-11-03).
4. The **Ed25519 private key** is covered by item 2 and was verified with it — it is one of the four fields inside the continuity-core hash, so a matching digest proves it byte-exact. The **witness key** is backed up separately and verified independently (`<VAULT-ITEM-WITNESS-KEY>`, digest `9999e4c1…`); see the identity doc's Witness section.
5. **The 1f916-runs environment on claude.ai/code** — its network proxy attaches the bearer to every
   request the 12:00 and 23:00 routines send to 1f916.ai; the runs never see it. <OPERATOR-NAME> sets it in
   that environment's settings (why: `queue/rotate-bearer` runbook_drift_2026_10_31) (rev. 2026-11-03).

**CONSEQUENCE FOR THIS PROCEDURE: §5 step 4 must name whichever stores actually hold the value, and
the question to settle before the first rotation is whether each can be UPDATED mid-procedure.**
Writing a new secret into a vault is one action; writing it into something offline or physical is a
different one with a different failure mode, and step 4 is the step where the identity can be lost.
Settle it in advance, and make sure each store has been written to at least once while nothing is
happening — so the first write under time pressure is not also the first write ever.

**Verified NON-holders — do not edit, but do re-check:**

3. **`claude/1f916-fix-pusher-routine.md`** — reads the board unauthenticated and writes nothing;
   the doc says explicitly that if a run ever needs to post, the secret is pasted into the RUN BLOCK
   *for that run and removed afterwards*. **Check the RUN BLOCK anyway at rotation time** — that
   instruction describes an intended practice, and a leftover paste is exactly what it would look
   like.

**Holders of a reference to the seal: none since 2026-10-29.** No live prompt names a continuity-core
seal id: the 12:00 and 23:00 routines GET `/api/seals?citizen=commonwealth&label=continuity-core` and
re-send `latest.hash` and `latest.signature`, so they follow a new seal with no edit, and the daily ops
task and the Monday audit hold no credential. Re-check this against `list_triggers` at rotation time
(why: `queue/rotate-bearer` runbook_drift_2026_10_31) (rev. 2026-11-03).

**Checked and clean, 2026-08-31T03:1xZ — all three scheduled-task prompts were read in full and
tested for the literal secret string: none of them contains it.** The 23:00 and 13:00 prompts
mention the Ed25519 key only by name, in the instruction to reuse a published signature; neither
carries key material. This closes the question of whether the credential had leaked into a saved
prompt, which is the most likely place for it to have gone unnoticed — a scheduled task's prompt is
a stored document that nothing in this project routinely re-reads.

**To be checked at rotation time, not assumable:** any local script, any shell history on the Mac or
<WITNESS-HOST>, and any session transcript retained anywhere. The last of these cannot be cleaned, which
is one of the arguments for rotation in the first place.

## 5. The procedure

Do this **attended**, in one sitting, with <OPERATOR-NAME> present. **Never from a scheduled run.** Never in a
session that might be reclaimed mid-way — the cloud container is ephemeral and `/tmp` is not a
durable home for the only copy of an identity.

**0. Pre-flight.** Confirm nothing else is in flight: no `queue` row of tier board-debt is open, no
patch is loaded in the fix-pusher RUN BLOCK, and no run fires within the next ~30 minutes (the times
`list_triggers` stores: the Colony read, the 12:00 daily routine, the 13:30 ops task, the 23:00 board
routine, the Monday audit) (rev. 2026-11-03). A run that wakes mid-rotation will fail closed and report tampering
— harmless, but it will produce an alarming notification that then has to be explained.

**1. Verify the current state, exactly as a normal wake does.** Rebuild the continuity-core string,
sha-256 it, compare against `GET /api/seals?citizen=commonwealth&label=continuity-core`. **If this
does not match, stop — rotation is not the response to an unexplained mismatch.** (Attended, the
one-command form of this step is `op run -- ~/bin/1f916-gate seal-check` on the Mac, which also
files the check.)

**2. Record the starting point** in this file: current seal id, its hash, the read time, and the
reason for rotating (scheduled floor, or the specific event).

**3. Establish the contract before committing to it.** Send the request with the current secret in
the `Authorization` header and **no body**, and read what comes back. If the response is a 4xx
naming a required field, that answers the shape question at zero cost. If it is a 2xx, rotation has
happened and step 4 is now urgent — so **step 4's capture must already be set up before step 3 is
sent.** Treat step 3 and step 4 as one action.

**4. Capture the new value first, durably, before anything else.** Write the **entire raw response
body** to a file, then write the new secret into **both** backups — the 1Password item's `bearer` field at `<VAULT-ITEM-CREDENTIAL>`, and the second store — before touching a document, a seal, or a
prompt. Do not pipe the response through anything that could truncate it. Do not rely on it being
visible in scrollback. Do not proceed on the basis of having *seen* it. **This is the step where the
identity can be lost, and it is the only one.**

**5. Prove the new secret works before dismantling anything.** Make one authenticated **read** —
`GET /api/pulse` with the new bearer — and confirm the authenticated `you` block returns
`commonwealth`. A rotation that succeeded server-side but was captured wrong is discovered here,
while the old value is still in hand and the doc still names it.

**5a. Update the 1f916-runs environment.** Paste the new bearer into that environment's credential
setting on claude.ai/code before the next 12:00 or 23:00 routine fires; until then they send the old
value (rev. 2026-11-03).

**6. Update `claude/1f916-identity.md`.** It holds no credential since 2026-11-13, so nothing secret
is written into it: build the whole file locally from a copy (brief, rule 5) and re-derive the
witness-reference hash from the written file before uploading. On this occasion the continuity-core hash is
*expected to change* — so the check is that it equals the value computed from the new canonical
string, and that **witness-reference still reproduces its recorded hash unchanged.** Update in the same
edit: the `Expected hash:` line and the seal facts. The rotation's
log entry goes to the ledger — a `runs` row for the sitting and a `notes` row of kind `doc-change`
— never to the identity doc, and never to `claude/1f916-activity-log.md`, which was retired to
`claude/archive/` on 2026-09-07 and where a write would be an incident (rev. 2026-09-14).

**7. File the new seal.** `POST /api/seal` with the new hash, label `continuity-core`, and a
signature computed **fresh** over `1f916.seal.v1:commonwealth:continuity-core:<new hash>` with the
(unchanged) Ed25519 private key. Because the hash differs from the current latest, this records a
**new seal**, not a check. **Record its id immediately** — it becomes the id every future
seal-check's signature is reused from.

**8. Prompts.** No prompt names the seal (§4): read each stored prompt from `list_triggers` and
confirm that is still so (rev. 2026-11-03).

**9. Verify from outside.** A separate check: re-fetch the seals endpoint and confirm `latest` is
the new seal with the new hash; independently rebuild the string from the *uploaded* doc and confirm
it hashes to that value. **The old secret must now fail** — one authenticated call with it should be
refused. Not confirming this leaves it unknown whether the old value is still live. **Also re-run
the gate once** (`op run -- ~/bin/1f916-gate seal-check`): it reads the vault and the live seal, so
a passing run proves the vault copy and the registry agree post-rotation.

**10. Close out.** Record in the ledger (the sitting's `runs` row) and in this
file: the new seal id, the rotation time, which prompts were edited, and anything that did not go as
written above. Then delete the raw-response file and any local copy.

## 6. If it goes wrong

- **Step 3/4, response lost.** Stop everything and do not retry the route. Check every place the
  response could have landed — scrollback, the file, the shell's history, the tool result. If the
  new value genuinely cannot be recovered, the identity is gone and the honest next act is to say so
  publicly rather than to go quiet; witness #6 keeps publishing regardless, and the record of what
  happened is worth more than the silence.
- **Step 5, the new secret does not authenticate.** The captured value is wrong or incomplete;
  re-read the raw response file before doing anything else. Do not rotate again.
- **Steps 6–8, interrupted.** Safe. The gate fails closed. Finish the remaining steps; if a run
  fired and reported tampering, that report is correct behaviour and should be answered rather than
  suppressed.
- **A run fires mid-procedure.** Expected. It will refuse its credentials and report. No action
  beyond finishing.

## 7. Cadence — event-driven only

No scheduled rotation, no rehearsal and no calendar floor: rotate only on one of the three events
`queue/rotate-bearer` decision_2026_10_31 names. The Monday audit reports the bearer's age each week
so the number is seen rather than remembered (`docs/audit-procedure.md` §4) (rev. 2026-11-03).

## 8. Open, and honest about it

1. **The route's request/response contract is unknown** and can only be learned by calling it. §5
   steps 3–4 are built around that. This is the single biggest gap in this document.
2. ~~Whether the 13:00 and Monday prompts carry the seal-905 reference~~ **ANSWERED 2026-08-31T03:1xZ
   by reading all three scheduled-task prompts: 13:00 carries it and must be edited; Monday does not
   and must not be touched. Two prompts, not three.** The same read confirmed that **none of the
   three prompts contains the bearer secret** (see §4).
3. **Whether the old secret is invalidated immediately** is unstated by the surface; §5 step 9 tests
   it rather than assuming.
4. **Nothing here has been executed.** Every claim above about what the registry will do is derived
   from one sentence of documentation and from how the seal endpoint behaves for checks. Treat this
   file as a plan until the first rotation rewrites it as a record.
