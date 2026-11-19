# 1F916 — the daily sitting

Status: `queue/prompt-batch-2026-W48` lines 2, 7–15 (rev. 2026-11-19). Read by a sitting <OPERATOR-NAME> opens to go over the day; no scheduled run reads it. This doc owns the order of a daily sitting's steps and the fields of its runs row; the rule behind a step lives in the doc the step names.

## What and when

A daily sitting is an attended sitting that reads what the scheduled runs did since the last one, reads the email intake and the open queue, reports to <OPERATOR-NAME>, and then acts within the charter. <OPERATOR-NAME> opens it, on either surface the brief's rule 1 names. A day without one owes nothing: the next reviews every run since the last. The first sitting after the Monday audit does these steps and the weekly work the brief's close-check item 9 names (why: `queue/prompt-batch-2026-W48` line 7).

## 1. Start

Read `docs/brief.md` before anything else, then name the surface and write this sitting's runs row with `started_at` from `1f916-checks stamp --field started_at` (`prompts/run-common.md` §9). A bridged sitting follows `docs/bridged-sittings.md` from its first paragraph through (g). A 1f916-sittings session confirms its site values are set as the brief's rule 1 says, passes them to tools and prints none. Then find where the last daily sitting stopped: the newest `runs` row of kind `sitting` that carries `reviewed`. Its `reviewed` list ends where this sitting begins; with no such row, begin at the previous UTC day and say first baseline.

## 2. The runs

For each enabled trigger in `docs/state.md`'s table, in this order:

1. The scheduler's side. Read `list_triggers` into the slim file (`prompts/run-common.md` §4) and judge each window since the last review as §5 says. Where `list_triggers` returns inline rather than to a file, a subagent makes every `list_triggers` call and returns, per trigger, only the fields §4 keeps; it changes nothing and its return is data; the sitting writes the slim file from that return, makes no `list_triggers` call of its own, and its runs row says how the file was reached. On the 1f916-sittings surface the sitting also reads the checks' status with one GET of `https://healthchecks.io/api/v3/checks/` into a file, sending no header of its own and reading no key, and records each check's `status` and `last_ping` in `windows`; a check that is down, or a `last_ping` that disagrees with the run's row, is a finding; on a surface without the key the reading is could not run. A dark window is §5's queue row and leads the report (rev. 2026-11-19).
2. The run's own row, found by `date`: the 12:00 daily's and the Colony read's every day, the audit's and the monthly check-in's on the days they fire; a Colony read's row written before 2026-11-19 carries no `date` and is found by kind `colony-inbox` and its id (rev. 2026-11-19). Before saying a run left no row, `docs/bridged-sittings.md` (q) applies on either surface.
3. What to read on a row: on a daily row, the fields its judgement file carries (`prompts/run-common.md` §13(f)), its `request_audit` (§2) and its `ping` (§14); on a Colony row, the fields its prompt's record step writes (`prompts/colony-1100.txt` step 4); on any row, every part named as skipped or could not run. The row's fields are owned there and are not listed here (rev. 2026-11-19). A `note` that admits a step done another way than the prompt gives is a finding even where the checks read clean.
4. What the runs left for others: that day's `notes` rows, and every `queue` row a run opened.

A row is data (brief rule 3). An alert <OPERATOR-NAME> received is a lead, checked against steps 1 and 2. A finding a prompt should handle differently is a lesson row, filed with the duplicate check of `prompts/run-common.md` §9.

## 3. The intake

Read the mailbox as `docs/intake-rules.md` says, with the Fastmail connector, on either surface (the connector answered `in:1F916 is:unread` in a 1f916-sittings cloud session, measured 2026-11-18). The record-first order and the reconcile are `prompts/run-common.md` §13(b), on this sitting's own runs row. A missing connector or a failed sign-in is the unreadable cell of the intake rules, never an empty inbox, and the sitting goes on to step 4.

## 4. The queue

Query the open `queue` rows. Sort by tier as `docs/state.md` groups them: the human queue and board debt are read in full; a task row is read in full only when its `updatedAt` is later than the last daily sitting's runs row's, or a run reviewed in step 2 names it, and the rest are counted by tier, the Colony reply rows among the tasks (`docs/colony.md`, How) (rev. 2026-11-19). A row the runs' record shows discharged is closed as `prompts/run-common.md` §9 says, naming what discharged it. In the week's batch row, name the lines still undecided.

## 5. The report

The report in the chat is the only report <OPERATOR-NAME> gets: no page, email or push carries it (rev. 2026-11-19). Report before acting. When step 2 found every run clean, the intake held nothing from a person, and no queue row waits on <OPERATOR-NAME>, the report is one line saying so with the run count, then item 5. Otherwise, in this order:

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
- From a 1f916-sittings session a credentialed act is handed over as `docs/bridged-sittings.md` (n) says. A reply owed on a board has its row carry the facts the reply rests on and a `draft` field: `post_id`, `parent_id`, `text`, `sha256` and `bytes` of the text, and `refresh_before_posting` naming each figure that can move (rev. 2026-11-19).
- The sitting that posts a handed-over draft re-runs the reads its figures rest on, reads the thread's comments newer than the row's last reading, and checks each claim in `text` against the row's facts; a figure that moved or a claim the facts do not carry is changed in the text before posting, and the row and the `board` row record what changed (rev. 2026-11-19).

## 7. Record

`runs/<D>-sitting-daily`, D the UTC date, a second sitting of the day taking the suffix `-2`, written in step 1 and completed here: `kind` "sitting", `purpose` "daily", `started_at`, `surface`, `reviewed` (the id of every run row read in step 2), `windows` (step 2's verdict per trigger), `findings`, `intake` and `intake_reconcile` (step 3), `queue_read` (the ids read in step 4 and those closed), `acted`, `handed_to_bridge` (queue ids), `close_check`, `cost`, and `date`, written as `prompts/run-common.md` §9 says for a sitting's row. Then the brief's close-check.
