#!/usr/bin/env python3
"""prompts/redact.py — turn a STORED trigger prompt into the public template beside it.

    python3 prompts/redact.py <stored-prompt.txt> <values.json> > prompts/<file>.txt

The private values never live in this repository. <values.json> is kept in the operator's private
project and maps each placeholder below to the literal it replaces, plus the operator's given name
and GitHub login:

    {"<LEDGER-ARTIFACT-URL>": "...", "<WITNESS-REPO>": "owner/repo", "<OPERATOR-FORK>": "owner/repo",
     "<OPERATOR-GITHUB-LOGIN>": "...", "<INTAKE-ADDRESS>": "...", "<BOUND-DOMAIN>": "...",
     "<WITNESS-HOST>": "...", "<RUN-HOME>": "/home/...", "<OPERATOR-NAME>": "...",
     "<VAULT-ITEM-CREDENTIAL>": "op://<vault>/<item>", "<VAULT-ITEM-WITNESS-KEY>": "op://<vault>/<item>",
     "<OPERATOR-MAC-HOME>": "/Users/...", "<OPERATOR-EMAIL-PERSONAL>": "...",
     "<OPERATOR-EMAIL-ICLOUD>": "...", "<OPERATOR-EMAIL-ICLOUD-2>": "...",
     "OPERATOR_FULL_NAME": "...", "OPERATOR_NAME": "..."}

Every key of the form <NAME> is a placeholder; the values file, not this file, says which exist.
Longer literals are replaced before the shorter ones they contain (the witness repo before the fork
before the login; the intake address before the bound domain). The operator's full name, then given
name, become "the operator" and the handful of pronoun phrases that name a person become neutral.
Since 2026-09-21 the stored prompts and the published docs carry the placeholders themselves, so
this program is the leak check (`leak_check`) and the one-time converter, not a per-revision step.

Proven 2026-09-13 to reproduce all four templates then in the repository byte-for-byte from the
stored prompts. The weekly audit's leak check greps each template for the same literals; a hit means
a personal reference entered a stored prompt after this list was written and passed the byte-diff.
"""
import json
import sys

def placeholder_order(values):
    """Every key that looks like a placeholder, longest literal first, so a literal that
    contains another (the witness repo contains the login; the intake address contains
    the bound domain) is replaced before the one it contains. The values file, not this
    file, says which placeholders exist."""
    return sorted((k for k in values if k.startswith("<") and k.endswith(">") and values[k]),
                  key=lambda k: -len(values[k]))


def phrase_subs(name):
    """Sentences that name the operator or their configuration choices, made neutral."""
    return [
        (f"{name} toggles these tasks between Opus and Fable on purpose, so",
         "the configured model may change at any time without notice, so"),
        ("the `1F916 daily check-in — 12:00 UTC` row", "this task's row"),
        ("the `1F916 evening reply check — 23:00 UTC` row", "this task's row"),
        (name.upper(), "THE OPERATOR"),
        (name, "the operator"),
        ("and the first is the one he actually reads.", "and the first is the one they actually read."),
        ("so he can follow one if he wants.", "so a reader can follow one."),
        ("tells him nothing", "tells them nothing"),
        ("tells him something", "tells them something"),
        ("signed at his keyboard", "signed at their keyboard"),
    ]


def redact(text, values):
    full = values.get("OPERATOR_FULL_NAME")
    if full:
        text = text.replace(full, "the operator")
    for ph in placeholder_order(values):
        text = text.replace(values[ph], ph)
    for old, new in phrase_subs(values["OPERATOR_NAME"]):
        text = text.replace(old, new)
    return text


def leak_check(template, values):
    """Return the literals that still occur in a template (the audit's check)."""
    return [k for k, v in values.items() if v and v in template]


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[2]) as f:
        values = json.load(f)
    with open(sys.argv[1]) as f:
        sys.stdout.write(redact(f.read(), values))
