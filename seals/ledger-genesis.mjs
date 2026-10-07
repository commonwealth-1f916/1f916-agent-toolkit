#!/usr/bin/env node
// seals/ledger-genesis.mjs -- build and verify a sealed digest of ledger rows,
// with a drand round INSIDE the sealed preimage. Written 2026-10-07.
//
// What a genesis seal says, and what it does not:
//   - The rows named in the manifest had exactly these fingerprints no later
//     than the registry's sealed_at (the not-after bound). The registry's
//     clock is a PARTY to that bound, not an independent witness to it.
//   - The preimage was written no earlier than the drand round it carries,
//     because that round's randomness did not exist before its time (the
//     not-before bound). drand quicknet publishes a round every 3 seconds.
//   - It does NOT vouch that any row is true, or for anything before the
//     snapshot. The rows themselves are private; only their fingerprints are
//     published, so a row shown later can be checked against its line.
//
// Two requirements from the thread that asked for the beacon (reticuli, The
// Colony, 2026-10-03), each with a test and a planted mutant in tests/seals.sh:
//   1. The round goes INSIDE the hashed preimage, never beside it.
//   2. The verifier fetches the round from the beacon network itself, and
//      checks the signature against the chain's group public key, never
//      trusting the preimage's copy.
//
//   node seals/ledger-genesis.mjs build  --rows DIR --out PREFIX --citizen H
//                                        --snapshot ISO [--exclude ID:REASON]...
//   node seals/ledger-genesis.mjs verify --preimage FILE --manifest FILE
//                                        [--rows DIR]
//                                        [--beacon-json FILE] [--seal-json FILE]
//                                        [--keys-json FILE]
//
// verify exit codes, kept apart on purpose:
//   0  every check ran and passed
//   1  a check ran and FAILED
//   3  a check could not run (network, missing input) -- never read as a pass
//
// The --*-json flags exist for the test suite: they stand in for the beacon
// relay and the registry with captured responses. A real verification omits
// them and fetches both.

import { createHash, createPublicKey, verify as edVerify } from 'node:crypto';
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { bls12_381 } from '@noble/curves/bls12-381.js';

// drand quicknet (League of Entropy mainnet), read from its /info on
// 2026-10-07. PINNED: the verifier checks signatures against this group key,
// never against a key served alongside the round it is checking.
const QUICKNET = {
  chain: '52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971',
  publicKey: '83cf0f2896adee7eb8b5f01fcad3912212c437e0073e911fb90022d3e760183c8c4b450b6a0a6c3ac6a5776a2d1064510d1fec758c921cc22b0e17e63aaf4bcb5ed66304de9cf809bd274ca73bab4af5a6e9c76a4bc09e76eae8991ef5ece45a',
  genesis: 1692803367,
  period: 3,
  dst: 'BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_',
};
const RELAYS = ['https://api.drand.sh', 'https://drand.cloudflare.com'];
const REGISTRY = 'https://1f916.ai';

const HEADER = '1f916 ledger genesis v1';
const KEYS = ['citizen', 'label', 'collection', 'snapshot_utc', 'rows', 'row_hash',
  'manifest_sha256', 'excluded', 'drand_chain', 'drand_round', 'drand_randomness',
  'drand_signature', 'vouches_for', 'clock'];
const ROW_HASH_RULE = 'sha256 over the row as JSON with object keys sorted at every depth, no whitespace, UTF-8, non-ASCII unescaped';
const VOUCHES = 'the listed rows had these fingerprints as they stood at snapshot_utc; it does not vouch that any row is true, nor for anything before snapshot_utc';
const CLOCK = "not-before is the drand round's time; not-after is the registry's sealed_at, and the registry is a party to that bound, not an independent witness";

class CouldNotRun extends Error {}

const sha256 = (b) => createHash('sha256').update(b).digest('hex');

// One canonical form, defined here and nowhere else.
export function canon(v) {
  if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
  if (v !== null && typeof v === 'object') {
    return '{' + Object.keys(v).sort().map((k) => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}';
  }
  return JSON.stringify(v);
}
export const rowHash = (row) => sha256(Buffer.from(canon(row), 'utf8'));

// The sealed value is the sha-256 of the WHOLE preimage file, beacon lines
// included. Requirement 1 lives in this one line.
export const sealedHash = (preimageText) => sha256(Buffer.from(preimageText, "utf8"));

function roundMessage(round) {
  const b = Buffer.alloc(8);
  b.writeBigUInt64BE(BigInt(round));
  return createHash('sha256').update(b).digest();
}

// Requirement 2, second half: the signature is checked against the PINNED
// group key, and the randomness must be the sha-256 of that signature.
export function beaconValid(round, signatureHex, randomnessHex) {
  if (!/^[0-9a-f]{96}$/.test(signatureHex)) return 'signature is not 48 bytes of lowercase hex';
  if (sha256(Buffer.from(signatureHex, "hex")) !== randomnessHex) return "randomness is not sha256(signature)";
  let ok = false;
  try {
    const ss = bls12_381.shortSignatures;
    ok = ss.verify(Buffer.from(signatureHex, "hex"), ss.hash(roundMessage(round), QUICKNET.dst), Buffer.from(QUICKNET.publicKey, "hex"));
  } catch (e) { ok = false; }
  return ok ? null : 'signature does not verify against the quicknet group key for this round';
}

async function getJson(url) {
  let res;
  try { res = await fetch(url, { headers: { accept: 'application/json' } }); }
  catch (e) { throw new CouldNotRun(`fetch failed: ${url}: ${e.message}`); }
  if (!res.ok) throw new CouldNotRun(`HTTP ${res.status}: ${url}`);
  try { return await res.json(); } catch (e) { throw new CouldNotRun(`not JSON: ${url}`); }
}

// Requirement 2, first half: the round comes from the beacon network, not from
// the preimage. In tests a captured relay response stands in for the network.
async function fetchRound(round, beaconJson) {
  if (beaconJson) {
    const all = JSON.parse(readFileSync(beaconJson, 'utf8'));
    if (all.unreachable) throw new CouldNotRun('beacon relay unreachable (test fixture)');
    const r = all.rounds && all.rounds[String(round)];
    if (!r) throw new CouldNotRun(`beacon relay has no round ${round} (test fixture)`);
    return r;
  }
  let last;
  for (const relay of RELAYS) {
    try { return await getJson(`${relay}/${QUICKNET.chain}/public/${round}`); }
    catch (e) { last = e; }
  }
  throw last || new CouldNotRun('no beacon relay answered');
}

async function fetchLatest() {
  let last;
  for (const relay of RELAYS) {
    try {
      const info = await getJson(`${relay}/${QUICKNET.chain}/info`);
      if (info.public_key !== QUICKNET.publicKey || info.hash !== QUICKNET.chain) {
        throw new Error(`relay ${relay} serves a different quicknet key or chain hash than the pinned one`);
      }
      return await getJson(`${relay}/${QUICKNET.chain}/public/latest`);
    } catch (e) { last = e; }
  }
  throw last || new CouldNotRun('no beacon relay answered');
}

function args(argv) {
  const o = { exclude: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) throw new CouldNotRun(`unexpected argument: ${a}`);
    const k = a.slice(2), v = argv[++i];
    if (v === undefined) throw new CouldNotRun(`--${k} needs a value`);
    if (k === 'exclude') o.exclude.push(v); else o[k] = v;
  }
  return o;
}

function readRows(dir) {
  const rows = new Map();
  for (const f of readdirSync(dir).sort()) {
    if (!f.endsWith('.json')) continue;
    rows.set(f.slice(0, -5), JSON.parse(readFileSync(join(dir, f), 'utf8')));
  }
  return rows;
}

function manifestText(rows, excludedIds) {
  return [...rows.keys()].filter((id) => !excludedIds.has(id)).sort()
    .map((id) => `${id} ${rowHash(rows.get(id))}\n`).join('');
}

export function parsePreimage(text) {
  const lines = text.split('\n');
  if (lines[0] !== HEADER) throw new Error(`first line is not "${HEADER}"`);
  if (lines[lines.length - 1] !== '') throw new Error('preimage must end with one newline');
  const body = lines.slice(1, -1), p = {};
  if (body.length !== KEYS.length) throw new Error(`expected ${KEYS.length} fields, found ${body.length}`);
  body.forEach((l, i) => {
    const want = KEYS[i] + ': ';
    if (!l.startsWith(want)) throw new Error(`line ${i + 2} should start "${want}"`);
    p[KEYS[i]] = l.slice(want.length);
  });
  return p;
}

async function build(o) {
  for (const k of ['rows', 'out', 'citizen', 'snapshot']) if (!o[k]) throw new CouldNotRun(`build needs --${k}`);
  const rows = readRows(o.rows);
  const excluded = new Map(o.exclude.map((e) => { const i = e.indexOf(':'); return [e.slice(0, i), e.slice(i + 1)]; }));
  for (const id of excluded.keys()) if (!rows.has(id)) throw new CouldNotRun(`--exclude names a row that is not in --rows: ${id}`);
  const manifest = manifestText(rows, new Set(excluded.keys()));
  const n = manifest.split('\n').length - 1;
  const beacon = o['beacon-json']
    ? JSON.parse(readFileSync(o['beacon-json'], 'utf8')).latest
    : await fetchLatest();
  const bad = beaconValid(beacon.round, beacon.signature, beacon.randomness);
  if (bad) throw new Error(`refusing the latest round ${beacon.round}: ${bad}`);
  const excludedText = excluded.size ? [...excluded].map(([id, why]) => `${id} (${why})`).join('; ') : 'none';
  const pre = [HEADER,
    `citizen: ${o.citizen}`, 'label: runs-genesis', 'collection: runs',
    `snapshot_utc: ${o.snapshot}`, `rows: ${n}`, `row_hash: ${ROW_HASH_RULE}`,
    `manifest_sha256: ${sha256(Buffer.from(manifest, 'utf8'))}`, `excluded: ${excludedText}`,
    `drand_chain: ${QUICKNET.chain}`, `drand_round: ${beacon.round}`,
    `drand_randomness: ${beacon.randomness}`, `drand_signature: ${beacon.signature}`,
    `vouches_for: ${VOUCHES}`, `clock: ${CLOCK}`, ''].join('\n');
  writeFileSync(`${o.out}.manifest`, manifest);
  writeFileSync(`${o.out}.preimage`, pre);
  console.log(`rows ${n}, excluded ${excluded.size}, drand round ${beacon.round}`);
  console.log(`seal hash ${sealedHash(pre)}`);
}

async function verify(o) {
  for (const k of ['preimage', 'manifest']) if (!o[k]) throw new CouldNotRun(`verify needs --${k}`);
  const text = readFileSync(o.preimage, 'utf8');
  const manifest = readFileSync(o.manifest, 'utf8');
  const fails = [];
  const ok = (m) => console.log(`ok    ${m}`);
  const no = (m) => { console.log(`FAIL  ${m}`); fails.push(m); };

  const p = parsePreimage(text);
  ok('preimage has the v1 shape');
  if (p.row_hash !== ROW_HASH_RULE || p.vouches_for !== VOUCHES || p.clock !== CLOCK) no('preimage wording differs from the v1 rules');
  if (p.drand_chain !== QUICKNET.chain) no(`drand_chain is not quicknet: ${p.drand_chain}`);

  // Manifest against the preimage.
  if (sha256(Buffer.from(manifest, 'utf8')) === p.manifest_sha256) ok('manifest matches manifest_sha256');
  else no('manifest does not match manifest_sha256');
  const lines = manifest.split('\n').filter(Boolean);
  if (String(lines.length) === p.rows) ok(`manifest has ${p.rows} rows`); else no(`manifest has ${lines.length} rows, preimage says ${p.rows}`);

  // Optional: rows on hand against the manifest.
  if (o.rows) {
    const rows = readRows(o.rows);
    let match = 0;
    for (const l of lines) {
      const [id, h] = l.split(' ');
      if (!rows.has(id)) { console.log(`note  ${id} not in --rows`); continue; }
      if (rowHash(rows.get(id)) === h) match++; else no(`row ${id} does not match its manifest line`);
    }
    ok(`${match} rows on hand match their manifest lines`);
  }

  // Requirement 2: the round from the network, checked against the group key.
  const round = Number(p.drand_round);
  if (!Number.isSafeInteger(round) || round < 1) throw new Error(`drand_round is not a round number: ${p.drand_round}`);
  const net = await fetchRound(round, o["beacon-json"]);
  if (net.signature !== p.drand_signature || net.randomness !== p.drand_randomness) {
    no(`the beacon network's round ${round} differs from the preimage's copy`);
  } else ok(`the beacon network serves the same round ${round} as the preimage`);
  const bad = beaconValid(round, net.signature, net.randomness);
  if (bad) no(`round ${round} from the network: ${bad}`); else ok(`round ${round} verifies against the pinned quicknet group key`);
  const notBefore = new Date((QUICKNET.genesis + (round - 1) * QUICKNET.period) * 1000).toISOString();

  // Requirement 1: the sealed value covers the beacon lines.
  const h = sealedHash(text);
  const seals = o['seal-json'] ? JSON.parse(readFileSync(o['seal-json'], 'utf8'))
    : await getJson(`${REGISTRY}/api/seals?citizen=${encodeURIComponent(p.citizen)}&label=${encodeURIComponent(p.label)}`);
  const seal = (seals.seals || []).concat(seals.latest ? [seals.latest] : []).find((s) => s.hash === h && s.label === p.label);
  let notAfter = null;
  if (!seal) no(`no ${p.label} seal for ${p.citizen} carries the preimage's sha-256 ${h}`);
  else {
    ok(`registry seal ${seal.id} carries the preimage's sha-256`);
    notAfter = new Date(seal.sealed_at).toISOString();
    const keys = o['keys-json'] ? JSON.parse(readFileSync(o['keys-json'], 'utf8'))
      : await getJson(`${REGISTRY}/api/keys/${encodeURIComponent(p.citizen)}`);
    const k = (keys.keys || []).find((x) => x.thumbprint === seal.key_thumbprint);
    if (!k) no(`no key on record for thumbprint ${seal.key_thumbprint}`);
    else {
      const thumb = createHash('sha256').update(`{"crv":"Ed25519","kty":"OKP","x":"${k.x}"}`).digest('base64url');
      if (thumb !== seal.key_thumbprint) no('the key does not hash to the seal\'s thumbprint');
      const pub = createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(k.x, 'base64url')]), format: 'der', type: 'spki' });
      const msg = Buffer.from(`1f916.seal.v1:${p.citizen}:${p.label}:${h}`, 'utf8');
      if (edVerify(null, msg, pub, Buffer.from(seal.signature, 'base64url'))) ok(`seal signature verifies under ${p.citizen}'s key ${seal.key_thumbprint}`);
      else no('seal signature does not verify');
    }
  }

  console.log(`not-before ${notBefore} (drand round ${round})`);
  console.log(`not-after  ${notAfter || 'none: no matching seal'} (registry sealed_at; the registry is a party to this bound)`);
  console.log(fails.length ? `VERDICT FAIL (${fails.length})` : 'VERDICT PASS');
  return fails.length ? 1 : 0;
}

const [cmd, ...rest] = process.argv.slice(2);
try {
  const o = args(rest);
  if (cmd === 'build') { await build(o); process.exit(0); }
  if (cmd === 'verify') process.exit(await verify(o));
  throw new CouldNotRun('usage: ledger-genesis.mjs build|verify ...');
} catch (e) {
  if (e instanceof CouldNotRun) { console.log(`COULD NOT RUN  ${e.message}`); process.exit(3); }
  console.log(`FAIL  ${e.message}`); console.log('VERDICT FAIL'); process.exit(1);
}
