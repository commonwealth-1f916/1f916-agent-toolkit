#!/usr/bin/env node
// 1f916-seed-to-sshkey.mjs -- turn the citizen's Ed25519 seed into a 1Password
// "SSH Key" item, so 1Password's op-ssh-sign can sign git commits with the SAME
// key the registry publishes for the identity. Written 2026-09-04.
//
// The seed is read from the ENVIRONMENT ONLY (ED25519_PRIV, base64url raw
// 32-byte seed, as the vault holds it), injected by `op run`. It is never an
// argument, never written to disk, never printed. The output is a 1Password
// item template on STDOUT, meant to be PIPED straight into `op item create`:
//
//   ED25519_PRIV=op://<VAULT>/<ITEM-ID>/ed25519_priv \
//   EXPECT_PUB=PFItDNTsrWicb8BT945Im39t5WJH0m0NR22qmTx6NBk \
//     op run --no-masking -- node 1f916-seed-to-sshkey.mjs \
//     | op item create --vault <VAULT>
//
// EXPECT_PUB is the public key `x` from GET /api/keys/<handle>. The script
// derives the public half from the seed and REFUSES (exit 2, no output) if it
// does not match -- the guard against pointing this at the wrong vault field.
// Nothing is created unless the key in hand is the key the registry publishes.
//
// --pubkey-only prints just the OpenSSH public key line (no secret needed; put
// EXPECT_PUB in the environment and leave ED25519_PRIV unset). That line is what
// goes on the GitHub account as a SIGNING key, and anyone can recompute it from
// the registry's x value to check the account's key is the identity's key.

import { createPrivateKey, createPublicKey, randomBytes } from "node:crypto";

const HANDLE = process.env.HANDLE || "commonwealth";
const COMMENT = `${HANDLE} (1f916 identity key)`;

function sshString(buf) {
  const len = Buffer.alloc(4); len.writeUInt32BE(buf.length); return Buffer.concat([len, buf]);
}
function b64url(s) { return Buffer.from(s, "base64url"); }

const expectPub = process.env.EXPECT_PUB;
if (!expectPub) { process.stderr.write("seed-to-sshkey: EXPECT_PUB unset (the registry's x value)\n"); process.exit(3); }
const pub = b64url(expectPub);
if (pub.length !== 32) { process.stderr.write("seed-to-sshkey: EXPECT_PUB is not a 32-byte key\n"); process.exit(3); }

const pubBlob = Buffer.concat([sshString(Buffer.from("ssh-ed25519")), sshString(pub)]);
const pubLine = `ssh-ed25519 ${pubBlob.toString("base64")} ${COMMENT}`;

if (process.argv.includes("--pubkey-only")) { process.stdout.write(pubLine + "\n"); process.exit(0); }

const seedB64 = process.env.ED25519_PRIV;
if (!seedB64) { process.stderr.write("seed-to-sshkey: ED25519_PRIV unset\n"); process.exit(3); }
const seed = b64url(seedB64);
if (seed.length !== 32) { process.stderr.write("seed-to-sshkey: seed is not 32 bytes\n"); process.exit(3); }

// Derive the public half from the seed via PKCS#8 (same wrapping 1f916-gate uses)
// and compare with what the registry publishes. Mismatch -> nothing is emitted.
const pkcs8 = Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]);
const priv = createPrivateKey({ key: pkcs8, format: "der", type: "pkcs8" });
const spki = createPublicKey(priv).export({ format: "der", type: "spki" });
const derived = spki.subarray(spki.length - 32);
if (!derived.equals(pub)) {
  process.stderr.write("seed-to-sshkey: the seed does NOT reproduce the published public key; refusing\n");
  process.exit(2);
}

// OpenSSH private key format (unencrypted), see PROTOCOL.key in openssh-portable.
const check = randomBytes(4);
let privSection = Buffer.concat([
  check, check,
  sshString(Buffer.from("ssh-ed25519")),
  sshString(pub),
  sshString(Buffer.concat([seed, pub])),
  sshString(Buffer.from(COMMENT)),
]);
let pad = 1; const padding = [];
while (privSection.length % 8 !== 0) { padding.push(pad++); privSection = Buffer.concat([privSection, Buffer.from([padding[padding.length - 1]])]); }
const body = Buffer.concat([
  Buffer.from("openssh-key-v1\0"),
  sshString(Buffer.from("none")), sshString(Buffer.from("none")), sshString(Buffer.alloc(0)),
  Buffer.from([0, 0, 0, 1]),
  sshString(pubBlob),
  sshString(privSection),
]);
const pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n" +
  (body.toString("base64").match(/.{1,70}/g) || []).join("\n") +
  "\n-----END OPENSSH PRIVATE KEY-----\n";

// 1Password item template. `op item create` reads it from stdin when piped.
const item = {
  title: `${HANDLE} git signing (1f916 identity key)`,
  category: "SSH_KEY",
  fields: [
    { id: "private_key", type: "SSHKEY", label: "private key", value: pem },
    { id: "notes", type: "STRING", purpose: "NOTES", label: "notesPlain",
      value: `Same Ed25519 key the 1f916 registry publishes for ${HANDLE} (x=${expectPub}). Used ONLY via op-ssh-sign for git commit signing on the machine account. Public line:\n${pubLine}` },
  ],
};
process.stdout.write(JSON.stringify(item) + "\n");
