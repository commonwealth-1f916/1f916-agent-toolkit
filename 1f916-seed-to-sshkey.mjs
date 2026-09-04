#!/usr/bin/env node
// 1f916-seed-to-sshkey.mjs -- the citizen's Ed25519 seed as an OpenSSH key, so
// git commits can be signed with the SAME key the registry publishes for the
// identity. Written 2026-09-04; reworked the same day (see below).
//
// Two modes, both taking EXPECT_PUB from the environment -- the public key `x`
// from GET /api/keys/<handle>:
//
//   --pubkey-only    print the OpenSSH PUBLIC line. No secret needed. This is
//                    what goes on the GitHub account as a SIGNING key, and it is
//                    a pure function of the registry's x, so anyone can recompute
//                    it and compare with the account's ssh_signing_keys.
//
//   --private-pem    print the OpenSSH PRIVATE key (unencrypted PEM) to stdout.
//                    The seed is read from the ENVIRONMENT ONLY (ED25519_PRIV,
//                    base64url raw 32-byte seed, as the vault holds it), injected
//                    by `op run`. Never argv, never a file, never printed except
//                    as this PEM on stdout -- which is meant to go into a PIPE,
//                    to `ssh-add -` inside 1f916-ssh-sign, and nowhere else.
//
// GUARD: the script derives the public half from the seed and REFUSES (exit 2,
// no output) unless it reproduces EXPECT_PUB. A key that is not the key the
// registry publishes is never emitted, whatever the vault field held.
//
// WHY NOT A 1PASSWORD SSH-KEY ITEM. The first version emitted an `op item
// create` template. 1Password CLI 2.39 cannot IMPORT an existing private key:
// a piped template creates nothing, `--template` creates an item op itself
// then cannot read ("private_key isn't a field"), and field assignment refuses
// the reserved field. Import is a desktop-app action, meaning the seed on disk
// or on the clipboard -- the two places this tooling exists to keep it out of.
// So there is no second copy: the seed stays in the one vault item, and
// 1f916-ssh-sign materialises it into a throwaway agent for one signature.

import { createPrivateKey, createPublicKey, randomBytes } from "node:crypto";

const HANDLE = process.env.HANDLE || "commonwealth";
const COMMENT = `${HANDLE} (1f916 identity key)`;

function sshString(buf) {
  const len = Buffer.alloc(4); len.writeUInt32BE(buf.length); return Buffer.concat([len, buf]);
}
function b64url(s) { return Buffer.from(s, "base64url"); }
function die(code, msg) { process.stderr.write(`seed-to-sshkey: ${msg}\n`); process.exit(code); }

const mode = process.argv[2];
if (mode !== "--pubkey-only" && mode !== "--private-pem") die(3, "usage: --pubkey-only | --private-pem (EXPECT_PUB in the environment; ED25519_PRIV via op run for --private-pem)");

const expectPub = process.env.EXPECT_PUB;
if (!expectPub) die(3, "EXPECT_PUB unset (the registry's x value)");
const pub = b64url(expectPub);
if (pub.length !== 32) die(3, "EXPECT_PUB is not a 32-byte key");

const pubBlob = Buffer.concat([sshString(Buffer.from("ssh-ed25519")), sshString(pub)]);
const pubLine = `ssh-ed25519 ${pubBlob.toString("base64")} ${COMMENT}`;

if (mode === "--pubkey-only") { process.stdout.write(pubLine + "\n"); process.exit(0); }

const seedB64 = process.env.ED25519_PRIV;
if (!seedB64) die(3, "ED25519_PRIV unset");
const seed = b64url(seedB64);
if (seed.length !== 32) die(3, "seed is not 32 bytes");

// Derive the public half from the seed via PKCS#8 (same wrapping 1f916-gate uses)
// and compare with what the registry publishes. Mismatch -> nothing is emitted.
const pkcs8 = Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]);
const priv = createPrivateKey({ key: pkcs8, format: "der", type: "pkcs8" });
const spki = createPublicKey(priv).export({ format: "der", type: "spki" });
if (!spki.subarray(spki.length - 32).equals(pub)) die(2, "the seed does NOT reproduce the published public key; refusing");

// OpenSSH private key format (unencrypted), see PROTOCOL.key in openssh-portable.
const check = randomBytes(4);
let privSection = Buffer.concat([
  check, check,
  sshString(Buffer.from("ssh-ed25519")),
  sshString(pub),
  sshString(Buffer.concat([seed, pub])),
  sshString(Buffer.from(COMMENT)),
]);
let pad = 1;
while (privSection.length % 8 !== 0) privSection = Buffer.concat([privSection, Buffer.from([pad++])]);
const body = Buffer.concat([
  Buffer.from("openssh-key-v1\0"),
  sshString(Buffer.from("none")), sshString(Buffer.from("none")), sshString(Buffer.alloc(0)),
  Buffer.from([0, 0, 0, 1]),
  sshString(pubBlob),
  sshString(privSection),
]);
// The armor line below is exempted BY ITS EXACT TEXT in tests/hygiene.sh: that
// scan hunts a committed key by its header, and a program that writes one is
// not its quarry. The exemption is the line, never the file.
const pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n" +
  (body.toString("base64").match(/.{1,70}/g) || []).join("\n") +
  "\n-----END OPENSSH PRIVATE KEY-----\n";
process.stdout.write(pem);
