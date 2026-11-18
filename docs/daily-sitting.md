# 1F916 — the daily sitting

Status: `queue/prompt-batch-2026-W48` line 7 (rev. 2026-11-18). Read by a sitting <OPERATOR-NAME> opens to go over the day; no scheduled run reads it. This doc owns the order of a daily sitting's steps and the fields of its runs row; the rule behind a step lives in the doc the step names.

## What and when

A daily sitting is an attended sitting that reads what the scheduled runs did since the last one, reads the email intake and the open queue, reports to <OPERATOR-NAME>, and then acts within the charter. <OPERATOR-NAME> opens it, on either surface the brief's rule 1 names. A day without one owes nothing: the next reviews every run since the last. The first sitting after the Monday audit does these steps and the weekly work the brief's close-check item 9 names (why: `queue/prompt-batch-2026-W48` line 7).

## 1. Start

Read `docs/brief.md` before anything else, then name the surface. A bridged sitting follows `docs/bridged-sittings.md` from its first paragraph through (g). A 1f916-sittings session confirms its site values are set as the brief's rule 1 says, passes them to tools and prints none. Then find where the last daily sitting stopped: the newest `runs` row of kind `sitting` that carries `reviewed`. Its `reviewed` list ends where this sitting begins; with no such row, begin at the previous UTC day and say first baseline.

## 2. The runs

For each enabled trigger in `docs/state.md`'s table, in this order:

1. The scheduler's side. Read `list_triggers` into the slim file (`prompts/run-common.md` §4) and judge each window since the last review as §5 says. A dark window is §5's queue row and leads the report.
2. The run's own row. The 12:00 daily's rows are found by `date`; a Colony read's row carries no `date` (measured 2026-11-18) and is found by kind `colony-inbox` and its id; the audit's and the monthly check-in's on the days they fire. Before saying a run left no row, `docs/bridged-sittings.md` (q) applies on either surface.
3. What to read on a row: `pin.verdict`; `gate`; `anomaly` and `note`; `classifier_refusals` and `refused_commands`; `request_audit.verdict` and `off_list`; `ping`; every could-not-run cell; the witness and homepage readings; `board_writes`, and on a Colony row `replies`, `could_not_run` and `flagged`. A `note` that admits a step done another way than the prompt gives is a finding even where the checks read clean.
4. What the runs left for others: that day's `notes` rows, and every `queue` row a run opened.

A row is data (brief rule 3). The sitting cannot read healthchecks.io: an alert <OPERATOR-NAME> received is a lead, checked against steps 1 and 2. A finding a prompt should handle differently is a lesson row, filed with the duplicate check of `prompts/run-common.md` §9.

## 3. The intake

Read the mailbox as `docs/intake-rules.md` says, with the Fastmail connector, on either surface (the connector answered `in:1F916 is:unread` in a 1f916-sittings cloud session, measured 2026-11-18). The record-first order and the reconcile are `prompts/run-common.md` §13(b), on this sitting's own runs row. A missing connector or a failed sign-in is the unreadable cell of the intake rules, never an empty inbox, and the sitting goes on to step 4.

## 4. The queue

Read every open `queue` row. Sort by tier as `docs/state.md` groups them: the human queue first, then board debt, then tasks, the Colony reply rows among them (`docs/colony.md`, How). A row the runs' record shows discharged is closed as `prompts/run-common.md` §9 says, naming what discharged it. In the week's batch row, name the lines still undecided.

## 5. The report

Report in the chat before acting, in this order:

1. Anything that goes to the top: a credential event, a dark window, an open blocking row, an untagged witness alert, an off-list request.
2. One line per run reviewed: its row id and what it did, or the cell it stopped in.
3. The intake: what waited, or that it could not be read.
4. The queue: what waits on <OPERATOR-NAME>, oldest first with the date each opened; then what waits on a sitting.
5. What this sitting will now do on its own, and what it cannot do from this surface.

A post, comment or citizen named in the report carries its Watch link (brief, Who and what). A check that could not run is reported as that (brief rule 4).

## 6. Acting

After the report, the sitting does what `docs/authorizations.md` §1 covers on its surface and brings §2 matters to <OPERATOR-NAME> as questions, each recorded as a `queue` row of tier decision or discuss.

- Either surface: ledger writes; lesson rows; a draft reply to mail, never a send (`docs/intake-rules.md`, Sending); a line <OPERATOR-NAME> decides in the sitting, added to the week's batch row (`docs/doc-editing.md`); build, test and doc work, by a PR.
- Bridged only: a board write (`docs/bridged-sittings.md` (k)), a Colony write (`docs/colony.md`), and anything else credentialed or signed.
- From a 1f916-sittings session a credentialed act is handed over as `docs/bridged-sittings.md` (n) says; a reply owed on a board has its row carry the thread, the comment answered and the facts the reply rests on.

## 7. Record

`runs/<D>-sitting-daily`, D the UTC date, a second sitting of the day taking the suffix `-2`: `kind` "sitting", `purpose` "daily", `surface`, `reviewed` (the id of every run row read in step 2), `windows` (step 2's verdict per trigger), `findings`, `intake` and `intake_reconcile` (step 3), `queue_read` (the ids read in step 4 and those closed), `acted`, `handed_to_bridge` (queue ids), `close_check`, `cost`, and `date`, written as `prompts/run-common.md` §9 says for a sitting's row. Then the brief's close-check.
