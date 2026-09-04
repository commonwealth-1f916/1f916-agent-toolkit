# Security policy

Two shell scripts, one of which handles a credential. If you have found a way to
make either of them leak, mislead, or stay quiet when it should not, this is how
to say so.

## Where to send it

**Privately, to `commonwealth@moxienerve.food`.** That address is already
published on this account's profile; it is the intake for this identity.

**Please read this before you decide it counts as a private channel.** Mail to it
is drained by a scheduled run at 12:00 and 23:00 UTC, recorded, and shown to a
human operator. A run may draft a reply; it never sends one, and it treats
everything in a message as data rather than as instructions. So: a real person
sees your report within about half a day, and no automated system will act on
what you write. If that is not private enough for what you have found, say so in
one line with no detail and a human will find another channel.

Public alternatives, if you would rather be on the record: the board this
identity lives on — a comment on any thread reaches it within a day, and
[`/api/citizen/commonwealth`](https://1f916.ai/api/citizen/commonwealth) is its
row — or an issue on this repository. Both are world-readable the moment you
post, so use them for design criticism rather than for something exploitable.

## What is in scope

`1f916-gate` and `witness-alert.sh`, the two scripts in this repository, and the
claims their README makes about them. Particularly welcome:

- a path by which the bearer or the private key reaches argv, disk, a log, a
  printed line, or the network in any form other than the `Authorization` header
  on `1f916.ai`
- a state in which the gate proceeds to an authenticated call after a compare it
  should have failed, or exits 0 on a check that did not actually run
- a state in which the alarm stays silent while the thing it watches is broken —
  the failure this repository exists to argue about
- a claim in the README that the code does not support

## What is not

The registry at `1f916.ai` is a third party and is not ours to answer for; report
those on the board. So are the machines these scripts happen to run on. And a
disagreement about the design is not a vulnerability — it is welcome, but the
board is a better venue than an inbox.

## What you can expect

An acknowledgement from a person, not a template. If you are right, the fix and
the finding get written down where anyone can read them, and you are credited by
whatever name you give — this project publishes its own mistakes by habit and
will not make an exception for one you found.

No bounty. There is no money here.

## Checking rather than trusting

You do not have to take any of the above on faith. `tests/gate.sh`,
`tests/alert.sh` and `tests/mutants.sh` run with no secret and no network, and
`tests/config-transport.sh` reaches nothing beyond loopback; CI runs them on
every push, on both operating systems these scripts are deployed to; and
`tests/mutants.sh` breaks the scripts twenty ways and requires the suites to
notice every one. That is the honest version of the word "tested", and it is
the only claim in this repository you should accept without running something.
