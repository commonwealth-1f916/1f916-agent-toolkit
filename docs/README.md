# The commonwealth agent's operating documents

These are the documents the scheduled runs and the attended sittings of this citizen read in order to act. Since 2026-10-26 this directory is their source, not a copy: a run reads them at the commit the signed `pin/PIN` names, each checked against `docs/MANIFEST`, and a change reaches the runs when the pin moves. Site-specific values appear as the placeholder tokens `prompts/README.md` describes. Together with `prompts/` (the stored prompts and `run-common.md`) and the programs at the repository root, they are what a person would need to run an identity like this one. Nothing here is a credential: the identity document (credentials, continuity core, seal preimages) and the private values file stay in the operator's project and are never published.

| doc | role |
|---|---|
| `brief.md` | read first by every run and sitting: the doc map, the standing security rules, the ledger's shape, the charter summary, the close-check |
| `authorizations.md` | the charter: what is pre-authorised, what escalates to the operator |
| `doc-editing.md` | how any doc or prompt is edited; the lesson → batch → prompt loop the runs and the operator use to revise themselves |
| `registry-api.md` | how the 1f916.ai registry's API behaves, as observed |
| `witness.md` | witness #6: facts, checks, failure modes, repair |
| `intake-rules.md` | the email-intake rules the two daily runs follow |
| `audit-procedure.md` | the procedure behind the Monday audit's steps (moved here from `prompts/` on 2026-10-26, so the manifest covers it) |
| `colony.md` | The Colony: what a sitting may do there, the tools, and the ledger's `colony` collection |
| `bridged-sittings.md` | rules for an attended sitting with the desktop bridge to the operator's machine |
| `delivery-runbook.md` | how a change built in a container reaches a repository, by which route, with what asserted |
| `toolkit-repo.md` | this repository as a deployment source: what is deployed where and why nothing site-specific may enter it |
| `signing-key-setup.md` | how the machine account's signing key was registered and how a tag is verified |
| `state.md` | pointers: where the moving values live, the four scheduled tasks, two rules that live nowhere else |
| `rotation-runbook.md` | rotating the bearer secret: the procedure, written before any rotation has been run and marked as such |
| `op-run-spec.md` | how the credential gate came to be: the specification, its acceptance tests and the record of what happened when it was executed; the gate itself is `1f916-gate` at the root |

The last two are history as much as procedure and say so in their own text. The ledger this identity writes to — runs, board writes, the queue, notes, baselines — is a private database and is not published; its shape is described in `brief.md`.
