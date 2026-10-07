// tests/seals.mjs -- seals/ledger-genesis.mjs, offline.
//
// Two real drand quicknet rounds are captured below, so the BLS check runs
// against the real group key with no network. A throwaway Ed25519 key stands
// in for the citizen's, and captured-shape JSON stands in for the registry.
//
// The two requirements the tool exists to keep each have a test that only a
// correct verifier passes, and tests/mutants.sh plants the mistake each one
// guards against:
//   1. the round is INSIDE the sealed preimage   -> test 4
//   2. the round comes from the network and is checked against the group key
//                                                 -> tests 5, 6, 7, 8
//
//   node tests/seals.mjs [path/to/ledger-genesis.mjs]

import { spawnSync } from 'node:child_process';
import { generateKeyPairSync, sign, createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const TOOL = resolve(process.argv[2] || join(here, '..', 'seals', 'ledger-genesis.mjs'));

// Captured 2026-10-07 from https://api.drand.sh (quicknet).
const R1 = { round: 32843365, randomness: 'b52f06d016bbdf7bc21ef0ccb2d06c5c22e58873213cdf724e38783d25c03627', signature: '8a949557f356215ccf950a69774b675f95fa8b4514e0a5352fcf3fe0834c9f7c3e5c689d99f3ead3035de76cc663a3e0' };
const R2 = { round: 32843366, randomness: '493239f8b23cbf5748421bcb45de23443b9da730a63227ed2ac8100d203f35f5', signature: '9576f47f2b6c45b99d4636d5b1ecdb6be75b9d9f421e66b9ee0965a2fca7cc33d7f73f9bf74507da825a2739bc914838' };

const sha256 = (s) => createHash('sha256').update(s).digest('hex');
const W = mkdtempSync(join(tmpdir(), 'seals-'));
let n = 0, failed = 0;
const ok = (c, m, why = '') => { n++; if (c) console.log(`ok ${n} - ${m}`); else { failed++; console.log(`not ok ${n} - ${m}${why ? ' -- ' + why : ''}`); } };

function tool(...a) {
  const r = spawnSync(process.execPath, [TOOL, ...a], { encoding: 'utf8' });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
}

// A throwaway citizen key, and the registry's two read shapes built from it.
const { publicKey, privateKey } = generateKeyPairSync('ed25519');
const x = publicKey.export({ format: 'jwk' }).x;
const thumb = createHash('sha256').update(`{"crv":"Ed25519","kty":"OKP","x":"${x}"}`).digest('base64url');
const keysJson = join(W, 'keys.json');
writeFileSync(keysJson, JSON.stringify({ keys: [{ x, thumbprint: thumb, status: 'active' }] }));

function sealFor(preText, key = privateKey, label = 'runs-genesis') {
  const h = sha256(Buffer.from(preText, 'utf8'));
  const sig = sign(null, Buffer.from(`1f916.seal.v1:tester:${label}:${h}`), key).toString('base64url');
  const f = join(W, `seal-${h.slice(0, 8)}-${n}.json`);
  writeFileSync(f, JSON.stringify({ latest: { id: 9001, hash: h, label, signature: sig, key_thumbprint: thumb, sealed_at: 1791333600000 } }));
  return f;
}
function beaconFile(rounds, extra = {}) {
  const f = join(W, `beacon-${n}-${Math.random().toString(36).slice(2)}.json`);
  const all = { latest: R1, rounds: {}, ...extra };
  for (const r of rounds) all.rounds[String(r.round)] = r;
  writeFileSync(f, JSON.stringify(all));
  return f;
}

// Three rows, one excluded, keys in an order canon() must not care about.
const rows = join(W, 'rows'); mkdirSync(rows);
writeFileSync(join(rows, 'a-run.json'), JSON.stringify({ kind: 'daily', n: 1, nested: { b: 2, a: [1, 'é'] } }));
writeFileSync(join(rows, 'b-run.json'), JSON.stringify({ written_by: 'evening', anomaly: false }));
writeFileSync(join(rows, 'c-sitting.json'), JSON.stringify({ kind: 'sitting', note: 'still being written' }));

// ---- build
const out = join(W, 'g');
let r = tool('build', '--rows', rows, '--out', out, '--citizen', 'tester', '--snapshot', '2026-10-07T00:00:00Z',
  '--exclude', 'c-sitting:the sitting that built this seal', '--beacon-json', beaconFile([R1]));
ok(r.code === 0, '1. build succeeds on a valid beacon round', r.out);
const pre = readFileSync(`${out}.preimage`, 'utf8');
const man = readFileSync(`${out}.manifest`, 'utf8');
ok(man.split('\n').filter(Boolean).length === 2 && !man.includes('c-sitting'), '1b. the excluded row is not in the manifest');
ok(pre.includes(`drand_round: ${R1.round}\n`) && pre.includes(`drand_signature: ${R1.signature}\n`), '1c. the round and its signature are lines OF the preimage');
r = tool('build', '--rows', rows, '--out', join(W, 'x'), '--citizen', 'tester', '--snapshot', 's', '--exclude', 'nope:x', '--beacon-json', beaconFile([R1]));
ok(r.code === 3, '1d. build refuses to exclude a row it does not have', r.out);
const forgedLatest = { ...R1, signature: R1.signature.slice(0, -1) + (R1.signature.endsWith('0') ? '1' : '0') };
forgedLatest.randomness = sha256(Buffer.from(forgedLatest.signature, 'hex'));
r = tool('build', '--rows', rows, '--out', join(W, 'y'), '--citizen', 'tester', '--snapshot', 's', '--beacon-json', beaconFile([], { latest: forgedLatest }));
ok(r.code === 1 && /refusing the latest round/.test(r.out), '1e. build refuses a round whose signature does not verify', r.out);

// canon() ignores key order: the same row written the other way round hashes the same.
const rows2 = join(W, 'rows2'); mkdirSync(rows2);
writeFileSync(join(rows2, 'a-run.json'), JSON.stringify({ nested: { a: [1, 'é'], b: 2 }, n: 1, kind: 'daily' }));
writeFileSync(join(rows2, 'b-run.json'), JSON.stringify({ anomaly: false, written_by: 'evening' }));

const seal = sealFor(pre);
const net = beaconFile([R1, R2]);
const v = (preFile, manFile, sealFile, beacon, ...more) => tool('verify', '--preimage', preFile, '--manifest', manFile, '--seal-json', sealFile, '--keys-json', keysJson, '--beacon-json', beacon, ...more);

// ---- 2. the honest case
r = v(`${out}.preimage`, `${out}.manifest`, seal, net, '--rows', rows2);
ok(r.code === 0 && /VERDICT PASS/.test(r.out), '2. a correct seal verifies', r.out);
ok(/2 rows on hand match/.test(r.out), '2b. rows written with keys in another order still match their lines', r.out);
ok(/not-before 2026-10-07T00:/.test(r.out), '2c. not-before is computed from the round number', r.out);

// ---- 3. the manifest and the rows
const manBad = join(W, 'bad.manifest'); writeFileSync(manBad, man.replace(/ [0-9a-f]{64}\n$/, ' ' + '0'.repeat(64) + '\n'));
r = v(`${out}.preimage`, manBad, seal, net);
ok(r.code === 1 && /manifest does not match/.test(r.out), '3. an edited manifest fails', r.out);
const rows3 = join(W, 'rows3'); mkdirSync(rows3);
writeFileSync(join(rows3, 'a-run.json'), JSON.stringify({ kind: 'daily', n: 2, nested: { b: 2, a: [1, 'é'] } }));
r = v(`${out}.preimage`, `${out}.manifest`, seal, net, '--rows', rows3);
ok(r.code === 1 && /row a-run does not match/.test(r.out), '3b. a row edited after the snapshot is named', r.out);

// ---- 4. REQUIREMENT 1: the round is inside the sealed value.
// Swap in a different, perfectly valid round and keep the seal. Only a
// verifier whose sealed hash covers the beacon lines notices.
const swapped = pre.replace(`drand_round: ${R1.round}`, `drand_round: ${R2.round}`)
  .replace(R1.randomness, R2.randomness).replace(R1.signature, R2.signature);
const swappedFile = join(W, 'swapped.preimage'); writeFileSync(swappedFile, swapped);
r = v(swappedFile, `${out}.manifest`, seal, net);
ok(r.code === 1 && /no runs-genesis seal/.test(r.out), '4. REQ 1: swapping the round under an existing seal fails', r.out);

// ---- 5. REQUIREMENT 2: the round comes from the network.
r = v(`${out}.preimage`, `${out}.manifest`, seal, beaconFile([], { unreachable: true }));
ok(r.code === 3 && /COULD NOT RUN/.test(r.out), '5. REQ 2: with the beacon relay unreachable the verdict is could-not-run, never pass', r.out);

// ---- 6. REQUIREMENT 2: a forged copy in the preimage, the real round on the network.
const forgedSig = R1.signature.slice(0, -1) + (R1.signature.endsWith('0') ? '1' : '0');
const forgedRand = sha256(Buffer.from(forgedSig, 'hex'));
const forgedPre = pre.replace(R1.signature, forgedSig).replace(R1.randomness, forgedRand);
const forgedFile = join(W, 'forged.preimage'); writeFileSync(forgedFile, forgedPre);
r = v(forgedFile, `${out}.manifest`, sealFor(forgedPre), net);
ok(r.code === 1 && /differs from the preimage's copy/.test(r.out), '6. REQ 2: a preimage whose copy of the round differs from the network fails', r.out);

// ---- 7. REQUIREMENT 2: a lying relay agrees with the forged copy; the group key does not.
r = v(forgedFile, `${out}.manifest`, sealFor(forgedPre), beaconFile([{ ...R1, signature: forgedSig, randomness: forgedRand }]));
ok(r.code === 1 && /does not verify against the quicknet group key/.test(r.out), '7. REQ 2: a forged round fails the group-key check even when the relay serves it', r.out);

// ---- 8. randomness must be sha256(signature)
const badRandPre = pre.replace(R1.randomness, '0'.repeat(64));
const badRandFile = join(W, 'badrand.preimage'); writeFileSync(badRandFile, badRandPre);
r = v(badRandFile, `${out}.manifest`, sealFor(badRandPre), beaconFile([{ ...R1, randomness: '0'.repeat(64) }]));
ok(r.code === 1 && /randomness is not sha256/.test(r.out), '8. a round whose randomness is not sha256(signature) fails', r.out);

// ---- 9. the seal's own signature
const other = generateKeyPairSync('ed25519').privateKey;
r = v(`${out}.preimage`, `${out}.manifest`, sealFor(pre, other), net);
ok(r.code === 1 && /seal signature does not verify/.test(r.out), '9. a seal signed by another key fails', r.out);

// ---- 10. the wording travels with the seal
const reworded = pre.replace('it does not vouch that any row is true', 'it vouches that every row is true');
const rewordedFile = join(W, 'reworded.preimage'); writeFileSync(rewordedFile, reworded);
r = v(rewordedFile, `${out}.manifest`, sealFor(reworded), net);
ok(r.code === 1 && /wording differs/.test(r.out), '10. a preimage that claims more than v1 says fails', r.out);

rmSync(W, { recursive: true, force: true });
console.log(`# ${n} tests, ${n - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
