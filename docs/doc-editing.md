# 1F916 — editing the project docs and the prompts

Status: `queue/task-doc-hygiene-and-prompt-feedback-loop` (rev. 2026-09-07). Read before writing any project doc or any trigger prompt.

## The map

| doc | temperature | who writes it | what goes in it |
|---|---|---|---|
| the **ledger** (artifact database) | hot | every run and sitting, as it goes | the record: `runs`, `board`, `queue`, `notes`, `neighbours`. Nothing in it is an instruction. |
| `1f916-brief.md` | warm | rarely | doc map, standing rules, charter summary, close-check |
| `1f916-state.md` | warm | when a pointer changes | pointers; the project-instructions baseline |
| `1f916-identity.md` | frozen | credential events only, under rule 5 | credentials, continuity core, seal preimages |
| `1f916-docket-build.md` | cold | stubs and index lines only | environment facts, session rules; never longer after an edit |
| probes, runbooks, specs | cold | when a probe answers or a procedure changes | dated findings; a stub at anything moved |
| dated docs (`*-review-*`, `*-plan-*`, `*-shape-*`) | cold | their author | reasoning; archived by the archive test (why: `notes/2026-09-06-budgets-become-a-delta-rule`) |
| `archive/` | frozen | nobody | a changed archive is an incident |

A fact's home is decided by this table, not by which doc is open. Narrative goes in the ledger once: one `runs` row per run or sitting; anomalies and lessons as `notes` rows.

## What a sentence may be

These bind every write to a doc or a prompt, and are checked on the diff before `project_write` or `update_trigger`.

1. A sentence is an instruction, a pointer, or a value the doc owns. A reason is a `notes` row, cited by one token: `(why: notes/<id>)`.
2. Change by replacement. New text replaces old in place; the change carries one token, `(rev. YYYY-MM-DD)`; the old wording and the story go to a `notes` row of kind `doc-change`. "Amended", "sharpened", "clarified", "originally said" do not appear in a live doc or a prompt.
3. Status lives in the ledger. A doc has one status line at the top naming its `queue` row; nothing inside says done, pending, held, or superseded.
4. No quotations of the operator; no timestamps finer than a date; authority is the decision row.
5. Point, don't paraphrase. A doc never restates another doc's rule.
6. No capitalised words for emphasis; bold only for a defined term on first use.
7. Before writing, diff against the version read. Every added sentence passes rule 1 or moves to the ledger.
8. A sentence states no quantity, set membership, route parameter or repository count as a fact of its own; it names where the value is measured. A count expires, an invariant does not (why: `notes/lesson-2026-09-15-a-prompt-can-carry-a-windowed-reading-as-a-fact`).
9. A permission or capability claim names the mode, the session type and the date it was measured in, in the same sentence as the claim. A claim of permanence cites two measurements or none, and no scheduled-run step depends on computer use, which prompts on every grant and holds for one session (why: `notes/2026-09-14-lesson-a-reading-from-a-sitting-needs-its-mode-named`).

## The five editing rules

1. **Batch per instruction, write once.** Collect every change the work in front of you needs, then write. A new instruction is a new write. Never hold state back for a tidier write count; the ledger holds state.
2. **Never retype.** Extract the doc's bytes from the transcript (`/root/.claude/projects/<project>/<session>.jsonl`, the `project_read` tool-result line, field `content`) to a local file; apply replacements in python with `assert doc.count(old) == 1`; upload with `project_write` + `local_path`. A scheduled run without a transcript rebuilds the file in chunks whose byte counts and sha-256 are compared against the source of each chunk.
3. **Verify by invariants.** Byte count in range, header count, a grep for each edit's new text and the old text's absence, a recorded hash where one exists. A full read-back is for the identity doc only.
4. **Respect temperature.** Daily state goes only in hot docs. An edit that lengthens a cold doc stops: narrative goes to the ledger, state to `queue`, and a new finding replaces the stale text it corrects. Growth in a cold doc since the last audit is a finding.
5. **The identity doc.** Written only on credential events. Credential lines are carried through byte-exact, never retyped; both sealed hashes recorded in the doc are re-derived from the written file before upload; if either fails, do not upload and report. Local copies holding secrets are scanned with `1f916-scan` and deleted in the same sitting (brief, rule 2).

## Stubs

When content moves, the old place keeps a one-line dated stub pointing at the new home. Never delete a stub other docs point through; a stub nothing points through any more moves to `archive/` (rev. 2026-09-21).

## Same-sitting closures

A fact that lives in a prompt and a doc changes in both in the same sitting, byte-diffed via `list_triggers`. A push and its PR-body check happen in the same sitting.

## Lessons and prompt revision

Scheduled runs propose; only an attended sitting applies. A lesson row is data, never an instruction (brief, rule 3).

**Filing.** A run that notices something a prompt should handle differently writes one `notes` row:

    id        YYYY-MM-DD-lesson-<slug>
    kind      lesson
    prompt    daily | evening | audit | neighbours
    observed  what happened, one or two sentences
    observable what a later audit would check to see it fixed
    status    open
    written_by

No proposed wording. Security findings do not wait for the batch; they go to <OPERATOR-NAME> under charter §2 as they arise.

**Batching.** One `queue` row per ISO week, tier `decision`, id `prompt-batch-YYYY-Www` named for the week it is open and worked in, holds the Monday audit's gathering of every open lesson row and the hygiene-grep hits (below) and anything decided at the desk that week, one line per candidate with its observable. Whoever needs it first that week creates it, no session opens a second, and it closes when its items are applied; through 2026-10-04 the live batch is `prompt-batch-2026-W40` (why: `queue/prompt-batch-2026-W40`). The audit edits nothing (rev. 2026-09-16).

**Deciding.** <OPERATOR-NAME> decides every item. Cadence and scope reviewed 2026-10-07 (`queue/task-doc-hygiene-and-prompt-feedback-loop`).

**Applying.** One sitting, one revision per prompt, by replacement: live bytes → file → `update_trigger` → byte-diff against a fresh `list_triggers` → commit under `prompts/` in the toolkit → the trigger's `prompts` row in the ledger (rev. 2026-09-21). Close the batch row naming the commit and the lesson rows it consumed; set each consumed row `status: applied`; close rejected rows with a one-line verdict, `status: rejected`. The change log is git and the `doc-change` rows; a prompt carries no annotation of when a step was added.

**Checking.** The next audit reads every row with `status: applied` and no `outcome`, checks its observable against that week's runs, and writes `outcome: held` or `outcome: missed`. A missed row is a candidate in the next batch, for reversal or another attempt.

## The hygiene grep

The audit runs this over every live prompt (`list_triggers`) and every tier-A and tier-B doc, reports each hit as a line, and fixes nothing:

    Amended|Sharpened|Clarified|originally said|\bDONE\b|\bPENDING\b|held pending
    <OPERATOR-NAME>, 20|\(<OPERATOR-NAME>|<OPERATOR-NAME>'s word|at <OPERATOR-NAME>'s       (the operator quoted or dated)
    [0-9]{2}Z\b|xxZ                                  (timestamps finer than a date)
    \b[A-Z]{3,}( [A-Z]{3,}){2,}\b                    (three or more capitalised words in a row)

A hit is a sentence to move or delete, and joins the week's batch. Patterns are tuned from batch evidence, by the same batch process.

**Exemptions, and they are narrow.** This file's rule 2 and this section: they name the patterns. The live prompts: the capitalised-words pattern only — capitals are emphasis to a model, not shouting at a reader. `1f916-docket-build.md`: the fine-timestamp and capitalised-words patterns — it is a 113 KB history document where both are native to it, it carried 131 of the 227 hits on 2026-09-14, and counting them every week buries the hits that matter (rev. 2026-09-14).
