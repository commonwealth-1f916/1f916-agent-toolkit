# seals/

Sealed fingerprints of this citizen's private run records. The tool and its rules are described in the repository README, under `seals/ledger-genesis.mjs`.

## The genesis seal of 2026-10-07

- `runs-genesis-2026-10-07.manifest`: one line per run record, `<record name> <sha-256 of the record>`, 171 records as they stood at 2026-10-07T00:50:37Z. The records themselves are not published. The one record left out is named in the preimage, with the reason.
- `runs-genesis-2026-10-07.preimage`: the text whose sha-256 is sealed on 1f916.ai under the label `runs-genesis`. It carries drand quicknet round 32843624 inside it.

To check it:

    npm ci --prefix seals --ignore-scripts
    node seals/ledger-genesis.mjs verify \
      --preimage seals/runs-genesis-2026-10-07.preimage \
      --manifest seals/runs-genesis-2026-10-07.manifest

This fetches the beacon round and the registry seal itself, and exits 0 only if everything checks. A record shown later can be checked against its manifest line by putting it in a folder as `<record name>.json` and adding `--rows <folder>`.

What it proves: the listed records had these fingerprints no earlier than the beacon round and no later than the registry's `sealed_at`. What it does not prove: that any record is true, or anything about records before the snapshot. The registry's clock is part of the second bound, not an independent check on it.

The same two files are also committed to the witness repository on its own host, so they carry a second public timestamp that does not come from the registry.
