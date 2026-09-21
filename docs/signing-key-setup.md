# Commit signing with the identity key — the operator's steps

Status: `queue/task-doc-hygiene-and-prompt-feedback-loop` (rev. 2026-09-17).

Decided by <OPERATOR-NAME> 2026-09-04T21:0xZ: the machine account `commonwealth-1f916` signs commits with the
citizen's own Ed25519 key (thumbprint `9-lTy9Wnw32g7OmBZikV-pVf5TLZZy8Sr_tB0DGxS3M`), not a separate
key. **Reworked 21:5xZ** after the first design failed on the Mac — see "What changed" at the end.
Recipe and rationale: toolkit PR #13 (`1f916-ssh-sign`, `1f916-seed-to-sshkey.mjs`, README "Commits
signed by the identity key"). This doc is the human half. Every step touches where a secret lives, so
every step is <OPERATOR-NAME>'s (charter §2); a session built and tested the tooling with throwaway keys and has
never held the seed.

**The design in one sentence:** the seed stays in the one vault item it already lives in; for each
signature, `1f916-ssh-sign` runs `op run` to turn it into an OpenSSH key on a pipe, loads that into a
throwaway `ssh-agent`, signs, and kills the agent. No second copy, no file, no argv.

## What is already true (no secret involved)

- The OpenSSH public line for the identity key, derived from the registry's `x` and checked against
  `ssh-keygen`:

      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDxSLQzU7K1onG/AU/eOSJt/beViR9JtDUdtqpk8ejQZ commonwealth (1f916 identity key)
      SHA256:q2yRbCWjFFYblk+Fb2yBiKBpl+PLM1SnhJX/veRUsOs

  Anyone recomputes it: `EXPECT_PUB=$(curl -s https://1f916.ai/api/keys/commonwealth | jq -r
  '.keys[0].x') node 1f916-seed-to-sshkey.mjs --pubkey-only`.
- The machine-account `gh` token carries `gist, read:org, repo, workflow` — **read from the Mac
  2026-09-07T17:0xZ by the freeze-then-verify probe, login asserted `commonwealth-1f916`, active
  account confirmed back at `<OPERATOR-GITHUB-LOGIN>` afterwards.** It does NOT carry `admin:ssh_signing_key`, which
  is what registering a signing key needs, and that is a browser login as the machine account
  (delivery runbook §6). **So step 3 below was completed by the BROWSER path, not by
  `gh auth refresh`** — the signing key is live (registered 2026-09-04, verifiable at
  `api.github.com/users/commonwealth-1f916/ssh_signing_keys`) while the token still lacks the scope.
  Scopes are `as_of`, never a property: re-read them rather than inheriting this line. *(Before
  2026-09-07 this bullet said "`repo` scope only" and was undated; `claude/1f916-toolkit-repo.md` §3
  said "both with `repo` scope", also undated. Neither was wrong; both were uncheckable.)*
- The vault item: `<VAULT-ITEM-CREDENTIAL>` (the same item the gate reads), field
  `ed25519_priv`.

## Steps, in this order

0. **Delete the malformed item from the first attempt.** `op item list` shows an SSH Key item
   `commonwealth git signing (1f916 identity key)`, id `ouiccmlo3pgwan27kq7fuledg4`, created
   at an earlier time, which `op` itself cannot read back (`"private_key" isn't a field`). It may hold the
   PEM in some shape 1Password does not recognise; it is a second copy of unknown state and serves
   nothing now. `op item delete ouiccmlo3pgwan27kq7fuledg4`, or in the app.
1. **Merge toolkit PR #13** and `git pull` in `~/Projects/1f916-agent-toolkit`. Then the deploy
   symlink, same shape as the gate's: `ln -s ~/Projects/1f916-agent-toolkit/1f916-ssh-sign ~/bin/1f916-ssh-sign`.
2. **The config file**, `~/.1f916-ssh-sign.conf`, mode 600 (copy `1f916-ssh-sign.conf.example`):

       SEED_REF="<VAULT-ITEM-CREDENTIAL>/ed25519_priv"
       EXPECT_PUB="PFItDNTsrWicb8BT945Im39t5WJH0m0NR22qmTx6NBk"

   `SEED_TOOL` can stay unset: the wrapper resolves its own symlink and finds the seed tool beside
   itself in the clone.
3. **Register the public line as a SIGNING key on the machine account** (not an authentication key).
   Browser: Settings → SSH and GPG keys → New SSH key → Key type *Signing Key*, paste the line above.
   Or:

       gh auth switch --user commonwealth-1f916
       gh auth refresh -h github.com -s admin:ssh_signing_key      # browser, machine account
       EXPECT_PUB=PFItDNTsrWicb8BT945Im39t5WJH0m0NR22qmTx6NBk \
         node ~/Projects/1f916-agent-toolkit/1f916-seed-to-sshkey.mjs --pubkey-only > /tmp/cw.pub
       gh ssh-key add /tmp/cw.pub --type signing --title 'commonwealth identity key (1f916 #943)'
       rm /tmp/cw.pub
       gh auth switch --user <OPERATOR-GITHUB-LOGIN>                                 # ALWAYS switch back

4. **Tell git to sign, scoped to this account's remotes only** — in `~/.gitconfig-1f916`, the file
   already included via `hasconfig:remote.*.url:https://github.com/commonwealth-1f916/**`, so
   <OPERATOR-GITHUB-LOGIN>'s repos are untouched:

       [gpg]
           format = ssh
       [gpg "ssh"]
           program = ~/bin/1f916-ssh-sign
           allowedSignersFile = ~/.config/git/1f916-allowed-signers
       [user]
           signingkey = key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDxSLQzU7K1onG/AU/eOSJt/beViR9JtDUdtqpk8ejQZ
       [commit]
           gpgsign = true
       [tag]
           gpgsign = true

   and `~/.config/git/1f916-allowed-signers` with one line:
   `321972176+commonwealth-1f916@users.noreply.github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDxSLQzU7K1onG/AU/eOSJt/beViR9JtDUdtqpk8ejQZ`
   so `git log --show-signature` verifies locally too.
5. **Prove it once**: in the toolkit clone, `git checkout -b zz-sign-test && git commit --allow-empty
   -m test && git log -1 --show-signature`, then `git checkout main && git branch -D zz-sign-test`.
   1Password should prompt for the `op run` read (per-application authorisation, so possibly once
   per terminal app rather than per commit); the log should say `Good "git" signature`. If the
   commit FAILS with `1f916-ssh-sign: could not load the signing key`, the seed tool refused — the
   vault field did not reproduce `EXPECT_PUB` — and nothing was signed; stop there.

## What a session does after step 5 (its half)

- Verify from outside: `curl -s https://api.github.com/users/commonwealth-1f916/ssh_signing_keys`
  carries the line above; the next pushed commit shows **Verified** on GitHub.
- On the bundle route, the Mac **re-signs** what the container built before pushing, by the command
  in `claude/1f916-delivery-runbook.md` §3 (rev. 2026-09-17). Trees are
  unchanged; commit SHAs change — so delivery runbook §4's "expect the SHA to differ" applies to
  Route B again, and the tree assertion is the pass, as it always was.
- Then, and only then, the board line <OPERATOR-NAME> asked for (`queue/board-debt-signing-recipe`).
- **No identity-doc edit is needed by this design**: the seed's homes are unchanged (the vault item
  and the identity doc). The first design would have added a second vault item; it did not happen.

## What changed, and why (21:3x–21:5xZ)

The first design emitted a 1Password "SSH Key" item template for `op item create`, then relied on
1Password's `op-ssh-sign`. <OPERATOR-NAME> ran it; `op` reported success; the app showed nothing; `op item
get` said `"private_key" isn't a field`. Probed on the Mac with throwaway keys: a piped template
creates nothing, `--template` creates the unreadable item, and field assignment refuses the reserved
field — 1Password CLI 2.39 cannot import an existing private key. Import is a desktop-app action,
which means the seed on disk or the clipboard. Rather than that, the seed now never leaves the vault
for anywhere that persists, which is a better property than the design it replaced had. The
alternative <OPERATOR-NAME> raised — generate a fresh key with `--ssh-generate-key` and use `op-ssh-sign` —
remains a legitimate two-command option; it loses the computable account-to-citizen link unless the
identity key signs a statement naming the new key, which would be one hop longer but still checkable.

## Why the coupling, stated once

One key, two protocols. SSH signatures are namespaced (`git`) and the seal preimage has its own
prefix (`1f916.seal.v1:`), so neither signature replays as the other. A compromise of the key
anywhere is a compromise everywhere, and rotating the identity key rotates the signing key. <OPERATOR-NAME>
chose this on purpose because the account *is* the citizen; a separate key would have been safer
and said less.
