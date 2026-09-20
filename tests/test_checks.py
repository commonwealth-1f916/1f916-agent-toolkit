"""tests/test_checks.py -- acceptance tests for 1f916-checks.

No network and no secret. Every fetch is served from tests/fixtures/checks/
through --offline-dir, and every git remote is a throwaway repository in a temp
directory reached by file:// URL. Run through tests/checks.sh.

The golden values are the ones the ledger stored on 2026-09-16 from the live
registry. They are not recomputed here from the fixture by the code under test;
they are literals, so a recipe that drifts cannot carry its expectation with it.
"""

import copy
import hashlib
import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "1f916-checks")
FIX = os.path.join(HERE, "fixtures", "checks")

GOLDEN_ROUTE = "7c49a733a74df314841ecbd99695bf42bea3708b03d51f9e690d14f363ad7135"
GOLDEN_CAPABILITY = "cc092aba7302c18248048c13a66a85e54c8d2caa888a22a5d2fc5e4f973d85f1"

SURFACE_URL = "https://1f916.ai/api/surface"
FRONT_URL = "https://1f916.ai/api/front?limit=100"
NEW_URL = "https://1f916.ai/api/new"
RECORD_URL = "https://1f916.ai/api/record/commonwealth"
WITNESS_URL = "https://witness.example.invalid/countersignatures.jsonl"
HOME_LIVE = "https://commonwealth.moxienerve.food/"
HOME_REPO = ("https://raw.githubusercontent.com/commonwealth-1f916/"
             "commonwealth.moxienerve.food/main/index.html")


def seal_url(label):
    return "https://1f916.ai/api/seals?citizen=commonwealth&label=" + label


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fixture_bytes(name):
    with open(os.path.join(FIX, name), "rb") as fh:
        return fh.read()


def fixture_json(name):
    return json.loads(fixture_bytes(name).decode("utf-8"))


def load_module():
    loader = importlib.machinery.SourceFileLoader("checks_under_test", SCRIPT)
    spec = importlib.util.spec_from_loader("checks_under_test", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def git_env():
    env = dict(os.environ)
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_AUTHOR_NAME"] = env["GIT_COMMITTER_NAME"] = "fixture"
    env["GIT_AUTHOR_EMAIL"] = env["GIT_COMMITTER_EMAIL"] = "fixture@example.invalid"
    return env


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="checks-test-")
        self.offline = os.path.join(self.tmp, "offline")
        os.mkdir(self.offline)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def serve(self, url, data):
        if isinstance(data, (dict, list)):
            data = json.dumps(data).encode("utf-8")
        with open(os.path.join(self.offline, sha(url.encode("utf-8"))), "wb") as fh:
            fh.write(data)

    def write(self, name, data):
        path = os.path.join(self.tmp, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if isinstance(data, (dict, list)):
            data = json.dumps(data).encode("utf-8")
        if isinstance(data, str):
            data = data.encode("utf-8")
        with open(path, "wb") as fh:
            fh.write(data)
        return path

    def run_checks(self, *args, **kw):
        want = kw.get("want", 0)
        cmd = [sys.executable, SCRIPT] + list(args)
        if kw.get("offline", True):
            cmd += ["--offline-dir", self.offline]
        env = git_env()
        env.update(kw.get("env_extra", {}))
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=env, input=kw.get("stdin"))
        self.assertEqual(p.returncode, want, "exit %d, stderr: %s stdout: %s" % (
            p.returncode, p.stderr.decode()[:500], p.stdout.decode()[:500]))
        if want == 64:
            return None
        self.assertTrue(p.stdout.endswith(b"\n"))
        out = json.loads(p.stdout.decode("utf-8"))
        self.assertEqual(out["version"], 1)
        self.assertEqual(out["check"], args[0])
        self.assertEqual(out["status"],
                         kw.get("status", "ok" if want == 0 else "could_not_run"))
        return out


# ---------------------------------------------------------------------------
class Surface(Base):
    def setUp(self):
        Base.setUp(self)
        self.payload = fixture_json("surface.json")
        self.prior = self.write("prior.json", fixture_bytes("prior-route-surface.json"))

    def test_fixture_reproduces_the_stored_digests(self):
        self.serve(SURFACE_URL, fixture_bytes("surface.json"))
        out = self.run_checks("surface")
        self.assertEqual(out["count"], 120)
        self.assertEqual(out["route_sha256"], GOLDEN_ROUTE)
        self.assertEqual(out["capability_sha256"], GOLDEN_CAPABILITY)
        self.assertEqual(out["digest_map"], fixture_json("prior-route-surface.json")["routes_digest_map"])
        self.assertIsNone(out["route_list_changed"])
        self.assertEqual(out["baseline_missing"], ["prior"])
        self.assertEqual(out["inputs"]["urls"][0]["url"], SURFACE_URL)

    def test_unchanged_against_the_stored_row_bare_and_wrapped(self):
        self.serve(SURFACE_URL, fixture_bytes("surface.json"))
        wrapped = self.write("wrapped.json", {"id": "route-surface", "version": 7,
                                              "data": fixture_json("prior-route-surface.json")})
        for prior in (self.prior, wrapped):
            out = self.run_checks("surface", "--prior", prior)
            self.assertFalse(out["route_list_changed"])
            self.assertFalse(out["capability_changed"])
            self.assertEqual(out["added"], [])
            self.assertEqual(out["removed"], [])
            self.assertEqual(out["changed_routes"], [])
            self.assertEqual(out["localised_by"], "routes_objects")
            self.assertEqual(out["prior"], {"count": 120, "route_sha256": GOLDEN_ROUTE,
                                            "capability_sha256": GOLDEN_CAPABILITY})

    def test_one_field_edit_moves_capability_only_and_names_the_route(self):
        edited = copy.deepcopy(self.payload)
        target = edited["routes"][5]
        line = "%s %s" % (target["method"], target["path"])
        target["summary"] = target["summary"] + " (edited)"
        self.serve(SURFACE_URL, edited)
        out = self.run_checks("surface", "--prior", self.prior)
        self.assertEqual(out["route_sha256"], GOLDEN_ROUTE)
        self.assertNotEqual(out["capability_sha256"], GOLDEN_CAPABILITY)
        self.assertFalse(out["route_list_changed"])
        self.assertTrue(out["capability_changed"])
        self.assertEqual(out["changed_routes"], [line])
        self.assertEqual(out["changed_fields"], {line: ["summary"]})

        # the digest map localises the same move when objects were never stored
        row = fixture_json("prior-route-surface.json")
        del row["routes_objects"]
        out = self.run_checks("surface", "--prior", self.write("nomap.json", row))
        self.assertEqual(out["localised_by"], "routes_digest_map")
        self.assertEqual(out["changed_routes"], [line])
        self.assertIn("routes_objects", out["baseline_missing"])

        del row["routes_digest_map"]
        out = self.run_checks("surface", "--prior", self.write("neither.json", row))
        self.assertFalse(out["localisable"])
        self.assertIsNone(out["changed_routes"])

    def test_removed_route_and_routes_list_as_a_list(self):
        edited = copy.deepcopy(self.payload)
        gone = edited["routes"].pop(0)
        line = "%s %s" % (gone["method"], gone["path"])
        self.serve(SURFACE_URL, edited)
        row = fixture_json("prior-route-surface.json")
        row["routes_list"] = row["routes_list"] if isinstance(row["routes_list"], list) \
            else row["routes_list"].splitlines()
        for variant in (row, dict(row, routes_list="\n".join(row["routes_list"]) + "\n")):
            out = self.run_checks("surface", "--prior", self.write("p.json", variant))
            self.assertEqual(out["count"], 119)
            self.assertTrue(out["route_list_changed"])
            self.assertEqual(out["removed"], [line])
            self.assertEqual(out["added"], [])

    def test_emit_baseline_is_shaped_for_storage(self):
        self.serve(SURFACE_URL, fixture_bytes("surface.json"))
        b = self.run_checks("surface", "--emit-baseline")["baseline"]
        self.assertEqual(b["routes"], 120)
        self.assertEqual(b["sha256"], GOLDEN_ROUTE)
        self.assertEqual(b["capability_sha256"], GOLDEN_CAPABILITY)
        self.assertTrue(b["routes_list"].endswith("\n"))
        self.assertEqual(sha(b["routes_list"].encode("utf-8")), GOLDEN_ROUTE)
        self.assertEqual(len(b["routes_objects"]), 120)
        # stored back as a prior, the baseline compares clean
        out = self.run_checks("surface", "--prior", self.write("b.json", b))
        self.assertFalse(out["capability_changed"])
        self.assertEqual(out["changed_routes"], [])


class RedPath(unittest.TestCase):
    """The golden test must be able to go red. Break the canonical serialisation
    the ways someone plausibly would and require the golden values to reject it."""

    def golden(self, mod):
        routes = fixture_json("surface.json")["routes"]
        # raised explicitly, not `assert`: python -O would strip an assert and
        # turn this red-path check green for the wrong reason.
        if mod.route_sha256(routes) != GOLDEN_ROUTE:
            raise AssertionError("route digest drifted")
        if mod.capability_sha256(routes) != GOLDEN_CAPABILITY:
            raise AssertionError("capability digest drifted")

    def test_unbroken_module_passes(self):
        self.golden(load_module())

    def test_ensure_ascii_false_is_caught(self):
        mod = load_module()
        mod.canonical_json = lambda obj: json.dumps(obj, sort_keys=True, separators=(",", ":"),
                                                    ensure_ascii=False)
        with self.assertRaises(AssertionError):
            self.golden(mod)

    def test_default_separators_are_caught(self):
        mod = load_module()
        mod.canonical_json = lambda obj: json.dumps(obj, sort_keys=True)
        with self.assertRaises(AssertionError):
            self.golden(mod)

    def test_missing_trailing_newline_is_caught(self):
        mod = load_module()
        mod.route_list_text = lambda lines: "\n".join(sorted(lines))
        with self.assertRaises(AssertionError):
            self.golden(mod)


# ---------------------------------------------------------------------------
class Witness(Base):
    def setUp(self):
        Base.setUp(self)
        self.body = fixture_bytes("witness-head.jsonl")
        self.lines = self.body.splitlines(True)
        self.newest = json.loads(self.lines[-1])["at"]

    def independent_prefix(self, n):
        # a different construction from the script's find() loop, on purpose
        return sha(b"".join(self.lines[:n]))

    def test_prefix_matches_an_independent_hash(self):
        self.assertEqual(len(self.lines), 300)
        self.serve(WITNESS_URL, self.body)
        prior = self.write("pair.json", {"n": 250, "prefix_hash": self.independent_prefix(250)})
        out = self.run_checks("witness", "--url", WITNESS_URL, "--prior", prior,
                              "--now", "2026-09-17T00:00:00Z")
        self.assertEqual(out["lines"], 300)
        self.assertEqual(out["prior_n"], 250)
        self.assertEqual(out["prefix_sha256_now"], self.independent_prefix(250))
        self.assertTrue(out["prefix_match"])
        self.assertFalse(out["truncated"])
        self.assertEqual(out["appended"], 50)
        self.assertEqual(out["full_sha256"], sha(self.body))
        self.assertEqual(out["new_pair"], {"n": 300, "prefix_hash": sha(self.body)})
        self.assertEqual(out["refused_lines"], 0)
        self.assertEqual(out["refused_new"], 0)
        self.assertEqual(out["refused_new_scope"], "since_prior_n")

    def test_modified_early_line_flips_prefix_match(self):
        tampered = list(self.lines)
        tampered[2] = tampered[2].replace(b'"countersigned"', b'"countersigneD"')
        self.assertNotEqual(tampered[2], self.lines[2])
        self.serve(WITNESS_URL, b"".join(tampered))
        prior = self.write("pair.json", {"id": "x", "version": 3,
                                         "data": {"n": 250, "prefix_hash": self.independent_prefix(250)}})
        out = self.run_checks("witness", "--url", WITNESS_URL, "--prior", prior)
        self.assertFalse(out["prefix_match"])

    def test_fewer_lines_than_prior_is_a_result_not_a_failure(self):
        self.serve(WITNESS_URL, self.body)
        prior = self.write("pair.json", fixture_bytes("prior-witness-pair.json"))
        out = self.run_checks("witness", "--url", WITNESS_URL, "--prior", prior)
        self.assertEqual(out["prior_n"], 1216)
        self.assertTrue(out["truncated"])
        self.assertFalse(out["prefix_match"])
        self.assertIsNone(out["prefix_sha256_now"])
        self.assertEqual(out["appended"], 300 - 1216)

    def test_freshness_boundaries(self):
        self.serve(WITNESS_URL, self.body)
        mod = load_module()
        at = mod.parse_iso(self.newest)
        import datetime
        cases = [(120 * 60, "FRESH"), (120 * 60 + 1, "LATE"), (180 * 60, "LATE"),
                 (180 * 60 + 1, "STALE"), (0, "FRESH")]
        for seconds, want in cases:
            now = (at + datetime.timedelta(seconds=seconds)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
            out = self.run_checks("witness", "--url", WITNESS_URL, "--now", now)
            self.assertEqual(out["freshness"], want, "at +%ds" % seconds)
        self.assertEqual(out["age_minutes"], 0.0)

    def test_refused_lines_counted_old_and_new(self):
        extra = []
        for i in range(4):
            o = json.loads(self.lines[-1])
            o["status"] = "refused-inconsistent" if i != 1 else "countersigned"
            extra.append((json.dumps(o) + "\n").encode())
        body = b"".join(self.lines[:10]) + extra[0] + b"".join(self.lines[10:]) + b"".join(extra[1:])
        self.serve(WITNESS_URL, body)
        prior = self.write("pair.json", {"n": 301, "prefix_hash": sha(b"".join(body.splitlines(True)[:301]))})
        out = self.run_checks("witness", "--url", WITNESS_URL, "--prior", prior)
        self.assertEqual(out["refused_lines"], 3)
        self.assertEqual(out["refused_new"], 2)
        self.assertEqual(len(out["refused_examples"]), 2)
        self.assertEqual(out["refused_examples"][0]["status"], "refused-inconsistent")
        self.assertTrue(out["prefix_match"])

    def test_refused_new_without_a_usable_n_counts_the_whole_file(self):
        # A prior row without an integer n used to leave refused_new null while
        # refused_lines counted the file, and the daily reads refused_new 0 as
        # the pass. Now the count is over the whole file and the scope says so.
        o = json.loads(self.lines[5])
        o["status"] = "refused-inconsistent"
        body = b"".join(self.lines[:5]) + (json.dumps(o) + "\n").encode() + b"".join(self.lines[6:])
        self.serve(WITNESS_URL, body)
        for prior_data, missing in (({"prefix_hash": "0" * 64}, ["n"]),
                                    ({"n": "250", "prefix_hash": "0" * 64}, ["n"]),
                                    (None, ["prior"])):
            args = ["witness", "--url", WITNESS_URL]
            if prior_data is not None:
                args += ["--prior", self.write("pair.json", prior_data)]
            out = self.run_checks(*args)
            self.assertEqual(out["baseline_missing"], missing)
            self.assertEqual(out["refused_new"], 1)
            self.assertEqual(out["refused_new_scope"], "whole_file")
            self.assertEqual(out["refused_examples"][0]["status"], "refused-inconsistent")
            self.assertIsNone(out["appended"])
            self.assertIsNone(out["prefix_match"])

    def test_no_trailing_newline_pairs_complete_lines_only(self):
        body = self.body[:-1]
        self.serve(WITNESS_URL, body)
        out = self.run_checks("witness", "--url", WITNESS_URL)
        self.assertFalse(out["ends_with_newline"])
        self.assertEqual(out["new_pair"], {"n": 299, "prefix_hash": self.independent_prefix(299)})


# ---------------------------------------------------------------------------
class Fetching(Base):
    def test_missing_offline_file_is_could_not_run_with_valid_json(self):
        out = self.run_checks("surface", want=3)
        self.assertIn("fetch failed", out["reason"])
        self.assertEqual(out["inputs"]["urls"][0]["url"], SURFACE_URL)
        self.assertNotIn("count", out)

    def test_unreadable_prior_is_could_not_run(self):
        self.serve(SURFACE_URL, fixture_bytes("surface.json"))
        out = self.run_checks("surface", "--prior", os.path.join(self.tmp, "absent.json"), want=3)
        self.assertIn("prior unreadable", out["reason"])
        self.assertNotIn("route_sha256", out)

    def test_unparseable_payload_is_could_not_run(self):
        self.serve(SURFACE_URL, b"<html>not json</html>")
        out = self.run_checks("surface", want=3)
        self.assertIn("unparseable", out["reason"])

    def test_usage_errors_exit_64(self):
        self.run_checks("witness", want=64)            # --url is required
        p = subprocess.run([sys.executable, SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(p.returncode, 64)
        self.assertEqual(p.stdout, b"")

    def test_hashes_expectations_and_cache_bust(self):
        self.serve("https://a.example.invalid/x", b"alpha\n")
        self.serve("https://b.example.invalid/y?v=1", b"beta\n")
        out = self.run_checks("hashes", "--url", "a=https://a.example.invalid/x",
                              "--url", "b=https://b.example.invalid/y?v=1",
                              "--expect", "a=" + sha(b"alpha\n"), "--expect", "b=" + "0" * 64,
                              "--cache-bust", "b")
        self.assertTrue(out["files"]["a"]["match"])
        self.assertFalse(out["files"]["b"]["match"])
        self.assertFalse(out["all_match"])
        self.assertEqual(out["files"]["b"]["url"], "https://b.example.invalid/y?v=1")
        fetched = [u["url"] for u in out["inputs"]["urls"]]
        self.assertTrue(fetched[1].startswith("https://b.example.invalid/y?v=1&cb="))
        out = self.run_checks("hashes", "--url", "a=https://a.example.invalid/x")
        self.assertIsNone(out["all_match"])
        self.assertIsNone(out["files"]["a"]["expected"])
        self.run_checks("hashes", "--url", "a=https://a.example.invalid/x", "--expect", "z=00", want=64)


# ---------------------------------------------------------------------------
class Seals(Base):
    def test_seal_latest_and_preimage(self):
        self.serve(seal_url("witness-reference"), fixture_bytes("seals-witness-reference.json"))
        pre = self.write("pre.txt", "not the preimage\n")
        out = self.run_checks("seal", "--label", "witness-reference", "--preimage", pre)
        live = fixture_json("seals-witness-reference.json")["latest"]
        self.assertEqual(out["latest"]["id"], live["id"])
        self.assertEqual(out["latest"]["hash"], live["hash"])
        self.assertEqual(out["latest"]["signature"], live["signature"])
        self.assertNotIn("checks", out["latest"])
        self.assertEqual(out["count"], 1)
        self.assertFalse(out["match"])

        body = b"line one\nline two\n"
        pre = self.write("pre2.txt", body)
        seal = fixture_json("seals-witness-reference.json")
        seal["latest"]["hash"] = sha(body)
        self.serve(seal_url("witness-reference"), seal)
        out = self.run_checks("seal", "--label", "witness-reference", "--preimage", pre)
        self.assertTrue(out["match"])
        self.assertEqual(out["preimage_bytes"], len(body))

    def test_homepage_three_way(self):
        page = fixture_bytes("homepage.html")
        self.serve(HOME_LIVE, page)
        self.serve(HOME_REPO, page)
        self.serve(seal_url("homepage"), fixture_bytes("seals-homepage.json"))
        out = self.run_checks("homepage")
        self.assertTrue(out["live_eq_repo"])
        self.assertFalse(out["repo_eq_seal"])
        self.assertFalse(out["agree"])
        self.assertEqual(out["seal_id"], fixture_json("seals-homepage.json")["latest"]["id"])
        self.assertIn("cb=", out["inputs"]["urls"][0]["url"])

        seal = fixture_json("seals-homepage.json")
        seal["latest"]["hash"] = sha(page)
        self.serve(seal_url("homepage"), seal)
        out = self.run_checks("homepage")
        self.assertTrue(out["agree"])
        self.assertEqual(out["live"], sha(page))


# ---------------------------------------------------------------------------
class Record(Base):
    def test_bindings(self):
        rec = fixture_json("record.json")
        self.serve(RECORD_URL, rec)
        thumb = rec["keys"][0]["thumbprint"]
        out = self.run_checks("bindings", "--expect-thumbprint", thumb)
        self.assertEqual(out["rows"], 2)
        self.assertTrue(out["all_verified"])
        self.assertEqual(out["not_verified"], [])
        self.assertEqual(out["active_keys"], [{"thumbprint": thumb, "custody": "self", "status": "active"}])
        self.assertTrue(out["thumbprint_ok"])
        self.assertEqual(out["model"], rec["model"])
        self.assertEqual(sorted(out["bindings"][0]), ["domain", "method", "status", "thumbprint"])

        rec["bindings"][1]["status"] = "pending"
        self.serve(RECORD_URL, rec)
        out = self.run_checks("bindings", "--expect-thumbprint", "not-" + thumb)
        self.assertFalse(out["all_verified"])
        self.assertEqual(out["not_verified"], [rec["bindings"][1]["domain"]])
        self.assertFalse(out["thumbprint_ok"])
        self.assertIsNone(self.run_checks("bindings")["thumbprint_ok"])

    def test_model_action_table(self):
        record = self.write("record.json", {"model": "model-a"})
        me = lambda rem: self.write("me%s.json" % rem, {"model_correction": {"remaining": rem, "resets_at": "2026-09-18T00:00:00Z"}})
        out = self.run_checks("model", "--configured", "model-a", "--record", record, "--me", me(1))
        self.assertEqual((out["equal"], out["action"], out["correction"]), (True, "none", None))
        out = self.run_checks("model", "--configured", "model-b", "--record", record, "--me", me(1))
        self.assertEqual((out["equal"], out["action"]), (False, "correct"))
        self.assertEqual(out["correction"], {"remaining": 1, "resets_at": "2026-09-18T00:00:00Z"})
        out = self.run_checks("model", "--configured", "model-b", "--record", record, "--me", me(0))
        self.assertEqual(out["action"], "blocked")
        out = self.run_checks("model", "--configured", "model-b", "--record", record)
        self.assertEqual((out["action"], out["correction"]), ("unknown", None))
        # the bindings output carries `model`, and the record can come on stdin
        out = self.run_checks("model", "--configured", "model-a", "--record", "-",
                              stdin=json.dumps({"check": "bindings", "model": "model-a"}).encode())
        self.assertEqual(out["action"], "none")


# ---------------------------------------------------------------------------
class Front(Base):
    def serve_front(self, posts, pins, board_total=500):
        self.serve(FRONT_URL, {"posts": posts, "board_total": board_total, "returned": len(posts)})
        self.serve(NEW_URL, {"pin_snapshot": ",".join(str(p) for p in pins), "pinned_extra": len(pins)})

    def test_fixture_against_stored_row(self):
        self.serve(FRONT_URL, fixture_bytes("front.json"))
        self.serve(NEW_URL, fixture_bytes("new.json"))
        prior = self.write("fm.json", fixture_bytes("prior-front-map.json"))
        out = self.run_checks("front", "--prior", prior)
        self.assertEqual(out["rows"], 101)
        self.assertEqual(out["pin_snapshot"], [23, 580, 610, 2321, 3326, 3434, 3544, 4658, 4870, 5348])
        self.assertEqual(out["pinned_in_window"], [5348])
        self.assertEqual(out["pinned_extra"], 10)
        self.assertFalse(out["pins_prior_missing"])
        self.assertEqual(out["pins_added"], [])
        self.assertEqual(out["pins_removed"], [])
        self.assertEqual(out["baseline"]["limit"], 100)

    def test_delta_ordering_and_pin_set_diff(self):
        posts = [{"id": 10, "comments": 5, "pinned": 1}, {"id": "11", "comments": 9, "pinned": 0},
                 {"id": 12, "comments": 4, "pinned": 0}, {"id": 13, "comments": 9, "pinned": 0},
                 {"id": 14, "comments": 1, "pinned": 0}]
        self.serve_front(posts, [10, 7, 3])
        prior = self.write("prior.json", {"data": {"map": {"10": 2, "11": 6, "12": 4, "13": 4, "99": 1},
                                                   "pins": ["3", "10", "8"], "read_ids": [12, 99]},
                                          "id": "front-map", "version": 2})
        out = self.run_checks("front", "--prior", prior, "--read-ids", "13,14")
        self.assertEqual([(d["id"], d["delta"]) for d in out["delta"]],
                         [(13, 5), (10, 3), (11, 3), (12, 0)])
        self.assertEqual(out["new_ids"], [14])
        self.assertEqual(out["dropped_ids"], [99])
        self.assertEqual(out["pins_added"], [7])
        self.assertEqual(out["pins_removed"], [8])
        self.assertEqual(out["read_ids_delta"], {"12": 4, "99": None})
        self.assertEqual(out["baseline"]["read_ids"], [13, 14])
        self.assertEqual(out["baseline"]["pins"], [3, 7, 10])
        self.assertEqual(out["map"]["11"], 9)

    def test_prior_without_pins(self):
        self.serve_front([{"id": 1, "comments": 1, "pinned": 0}], [5])
        prior = self.write("prior.json", {"map": {"1": 1}})
        out = self.run_checks("front", "--prior", prior)
        self.assertTrue(out["pins_prior_missing"])
        self.assertIsNone(out["pins_added"])
        self.assertEqual(out["baseline_missing"], ["pins", "read_ids"])
        self.assertIsNone(out["baseline"]["read_ids"])


# ---------------------------------------------------------------------------
class GitBase(Base):
    def git(self, cwd, *args, **env_extra):
        env = git_env()
        env.update(env_extra)
        subprocess.run(["git", "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main"] + list(args),
                       cwd=cwd, env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def new_repo(self, name):
        path = os.path.join(self.tmp, name)
        os.makedirs(path)
        self.git(path, "init", "-q")
        self.git(path, "symbolic-ref", "HEAD", "refs/heads/main")
        return path

    def commit_file(self, repo, rel, content, when=None, author_when=None, msg="c"):
        full = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(full) or repo, exist_ok=True)
        with open(full, "w") as fh:
            fh.write(content)
        self.git(repo, "add", rel)
        env = {}
        if when:
            env["GIT_COMMITTER_DATE"] = when
            env["GIT_AUTHOR_DATE"] = author_when or when
        self.git(repo, "commit", "-q", "-m", msg, **env)

    def url(self, path):
        return "file://" + path


class Docket(GitBase):
    def setUp(self):
        GitBase.setUp(self)
        up = self.new_repo("upstream")
        self.commit_file(up, "migrations/0001_init.sql", "a\n")
        self.commit_file(up, "migrations/0002_users.sql", "b\n")
        fork = os.path.join(self.tmp, "fork")
        subprocess.run(["git", "clone", "-q", up, fork], check=True, env=git_env())
        self.git(fork, "checkout", "-q", "-b", "claude/custody-declare")
        self.commit_file(fork, "migrations/0003_custody.sql", "c\n")
        self.commit_file(up, "migrations/0003_labels.sql", "d\n")
        self.commit_file(up, "README", "e\n")
        self.up, self.fork = up, fork

    def test_shared_number_and_next_free(self):
        out = self.run_checks("docket", "--upstream", self.url(self.up), "--fork", self.url(self.fork),
                              "--workdir", os.path.join(self.tmp, "wd"))
        self.assertEqual(out["upstream"]["repo"], self.url(self.up))
        self.assertEqual(out["upstream"]["ref"], "main")
        self.assertEqual(out["fork"]["ref"], "claude/custody-declare")
        self.assertEqual(out["upstream"]["numbers"], [1, 2, 3])
        self.assertEqual(out["fork"]["newest_migration"], "0003_custody.sql")
        self.assertEqual(out["shared_numbers"], [3])
        self.assertTrue(out["upstream_newest_ge_fork_newest"])
        self.assertEqual(out["next_free"], "0004")
        self.assertIsNone(out["behind"])
        self.assertEqual(out["behind_reason"], "not computed: shallow")

    def test_full_counts_behind(self):
        out = self.run_checks("docket", "--upstream", self.url(self.up), "--fork", self.url(self.fork),
                              "--full")
        self.assertEqual(out["behind"], 2)
        self.assertIsNone(out["behind_reason"])

    def test_missing_ref_is_could_not_run(self):
        out = self.run_checks("docket", "--upstream", self.url(self.up), "--fork", self.url(self.fork),
                              "--fork-ref", "no-such-branch", want=3)
        self.assertIn("not found", out["reason"])


class PushVerify(GitBase):
    def test_remote_bytes_against_local(self):
        base = os.path.join(self.tmp, "gh")
        repo = os.path.join(base, "commonwealth-1f916", "fixture-repo")
        os.makedirs(os.path.dirname(repo))
        os.makedirs(repo)
        self.git(repo, "init", "-q")
        self.git(repo, "symbolic-ref", "HEAD", "refs/heads/main")
        self.commit_file(repo, "tool", "#!/bin/sh\n")
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, stdout=subprocess.PIPE,
                              env=git_env()).stdout.decode().strip()
        self.serve("https://raw.githubusercontent.com/commonwealth-1f916/fixture-repo/%s/tool" % head, b"#!/bin/sh\n")
        self.serve("https://raw.githubusercontent.com/commonwealth-1f916/fixture-repo/%s/other" % head, b"remote\n")
        local = self.write("local-tool", b"#!/bin/sh\n")
        other = self.write("local-other", b"local\n")
        out = self.run_checks("push-verify", "--repo", "commonwealth-1f916/fixture-repo", "--ref", "main",
                              "--file", "tool=" + local, "--file", "other=" + other,
                              "--git-base", "file://" + base)
        self.assertEqual(out["sha"], head)
        self.assertTrue(out["files"]["tool"]["match"])
        self.assertFalse(out["files"]["other"]["match"])
        self.assertFalse(out["all_match"])


class WitnessGaps(GitBase):
    def test_committer_clock_gap_and_non_append(self):
        repo = self.new_repo("witness")
        path = "witness-state/countersignatures.jsonl"
        self.commit_file(repo, path, "1\n", when="2026-09-09T10:00:00Z")
        self.commit_file(repo, path, "1\n2\n", when="2026-09-10T10:00:00Z")
        self.commit_file(repo, path, "1\n2\n3\n", when="2026-09-10T11:00:00Z")
        # authored 30 min later, committed 200 min later: a gap only the committer clock shows
        self.commit_file(repo, path, "1\n2\n3\n4\n", when="2026-09-10T14:20:00Z",
                         author_when="2026-09-10T11:30:00Z")
        self.commit_file(repo, "unrelated", "x\n", when="2026-09-10T14:30:00Z")
        self.commit_file(repo, path, "1\nTWO\n3\n4\n5\n", when="2026-09-10T15:00:00Z",
                         author_when="2026-09-10T13:00:00Z")
        out = self.run_checks("witness-gaps", "--repo", self.url(repo), "--since", "2026-09-10T00:00:00Z")
        self.assertEqual(out["commits"], 4)
        self.assertEqual(out["max_gap_minutes"], 200.0)
        self.assertEqual(len(out["gaps_over"]), 1)
        self.assertEqual(out["gaps_over"][0]["minutes"], 200.0)
        self.assertEqual(out["gaps_over"][0]["to"], "2026-09-10T14:20:00Z")
        # on the author clock no gap exceeds 120 minutes
        self.assertEqual(out["author_clock_max_gap_minutes"], 90.0)
        self.assertEqual(len(out["non_append_commits"]), 1)
        self.assertEqual(out["non_append_commits"][0]["at"], "2026-09-10T15:00:00Z")

        out = self.run_checks("witness-gaps", "--repo", self.url(repo), "--gap-minutes", "100000")
        self.assertEqual(out["commits"], 5)
        self.assertEqual(out["gaps_over"], [])

    def hourly(self, repo, stamps):
        path = "witness-state/countersignatures.jsonl"
        body = ""
        for i, when in enumerate(stamps):
            body += "%d\n" % i
            self.commit_file(repo, path, body, when=when)

    def test_one_missed_tick_is_a_gap_on_the_boundary_and_below_it(self):
        # plumbline (c65503 on #3427): one missed hourly tick lands at exactly
        # 7200 s, and a strict > 120 let it through; an early next tick lands
        # below 120 and needs the 1.5x-cadence default.
        repo = self.new_repo("witness")
        self.hourly(repo, ["2026-09-10T10:07:00Z", "2026-09-10T11:07:00Z",
                           # 12:07 missed: exactly 120 minutes
                           "2026-09-10T13:07:00Z", "2026-09-10T14:07:00Z",
                           # 15:07 missed and 16:07 fired a minute early: 119 minutes
                           "2026-09-10T16:06:00Z", "2026-09-10T17:07:00Z"])
        out = self.run_checks("witness-gaps", "--repo", self.url(repo))
        self.assertEqual(out["gap_minutes"], 90.0)
        self.assertEqual([g["minutes"] for g in out["gaps_over"]], [120.0, 119.0])
        self.assertEqual(out["max_gap_minutes"], 120.0)

        # at 120 the boundary case is caught (>=) and the early tick is not
        out = self.run_checks("witness-gaps", "--repo", self.url(repo), "--gap-minutes", "120")
        self.assertEqual([g["minutes"] for g in out["gaps_over"]], [120.0])

    def test_drop_one_tick_counterfactual(self):
        repo = self.new_repo("witness")
        # a clean hourly run with jitter: every tick 60 min apart except one
        # that fired 2 min early and one 1 min late
        self.hourly(repo, ["2026-09-10T10:07:00Z", "2026-09-10T11:07:00Z", "2026-09-10T12:05:00Z",
                           "2026-09-10T13:07:00Z", "2026-09-10T14:08:00Z", "2026-09-10T15:07:00Z"])
        out = self.run_checks("witness-gaps", "--repo", self.url(repo))
        self.assertEqual(out["gaps_over"], [])
        sens = out["sensitivity_at_unit_failure"]
        self.assertEqual(sens["positions"], 4)
        self.assertEqual(sens["detected"], 4)
        self.assertEqual(sens["silent"], 0)
        self.assertEqual(sens["rate"], 1.0)

        # the old threshold is blind to most of the same drops: 120/118/121/120
        # merged gaps against >= 120 miss exactly the 118-minute one
        out = self.run_checks("witness-gaps", "--repo", self.url(repo), "--gap-minutes", "120")
        sens = out["sensitivity_at_unit_failure"]
        self.assertEqual((sens["detected"], sens["silent"]), (3, 1))
        self.assertEqual(sens["silent_examples"][0]["merged_minutes"], 118.0)
        self.assertEqual(sens["rate"], 0.75)

        # fewer than three commits: nothing to drop, and no rate is invented
        solo = self.new_repo("solo")
        self.hourly(solo, ["2026-09-10T10:07:00Z", "2026-09-10T11:07:00Z"])
        out = self.run_checks("witness-gaps", "--repo", self.url(solo))
        self.assertEqual(out["sensitivity_at_unit_failure"]["positions"], 0)
        self.assertIsNone(out["sensitivity_at_unit_failure"]["rate"])


class GitEnvironment(GitBase):
    def test_askpass_variables_never_reach_git(self):
        # GIT_ASKPASS and SSH_ASKPASS outrank the core.askPass= the program
        # passes, so they are removed from the child environment. Proved two
        # ways: an askpass that would fail loudly is never called, and a git
        # shim on PATH records the environment it was actually handed.
        repo = self.new_repo(os.path.join("commonwealth-1f916", "remote"))
        self.commit_file(repo, "f", "x\n")
        marker = os.path.join(self.tmp, "askpass-called")
        askpass = self.write("askpass.sh", "#!/bin/sh\ntouch '%s'\necho nope\nexit 1\n" % marker)
        os.chmod(askpass, 0o755)
        real_git = shutil.which("git")
        seen = os.path.join(self.tmp, "seen-env")
        shim_dir = os.path.join(self.tmp, "shim")
        os.mkdir(shim_dir)
        shim = os.path.join(shim_dir, "git")
        with open(shim, "w") as fh:
            fh.write("#!/bin/sh\nenv > '%s'\nexec '%s' \"$@\"\n" % (seen, real_git))
        os.chmod(shim, 0o755)
        env_extra = {"GIT_ASKPASS": askpass, "SSH_ASKPASS": askpass,
                     "GIT_CONFIG_PARAMETERS": "'credential.helper'='!%s'" % askpass,
                     "PATH": shim_dir + os.pathsep + os.environ.get("PATH", "")}
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, stdout=subprocess.PIPE,
                              env=git_env()).stdout.decode().strip()
        self.serve("https://raw.githubusercontent.com/commonwealth-1f916/remote/%s/f" % head, b"x\n")
        local = self.write("local-f", b"x\n")
        out = self.run_checks("push-verify", "--repo", "commonwealth-1f916/remote", "--ref", "main", "--file", "f=" + local,
                              "--git-base", "file://" + self.tmp, env_extra=env_extra, want=0)
        self.assertEqual(out["sha"], head)
        self.assertFalse(os.path.exists(marker))
        with open(seen) as fh:
            names = set(line.split("=", 1)[0] for line in fh.read().splitlines())
        self.assertIn("GIT_TERMINAL_PROMPT", names)
        for name in ("GIT_ASKPASS", "SSH_ASKPASS", "GIT_CONFIG_PARAMETERS"):
            self.assertNotIn(name, names)


# ---------------------------------------------------------------------------
class Window(Base):
    def triggers(self, last_run, wrap=True, extra=None):
        data = {"triggers": [{"id": "trig_1", "name": "daily 12:00 v2", "last_run": last_run},
                             {"id": "trig_2", "name": "evening 23:00 v2", "last_run": None}] + (extra or [])}
        return self.write("t.json", [{"type": "text", "text": json.dumps(data)}] if wrap else data)

    def test_dark_and_not_dark(self):
        ok = {"status": "SUCCEEDED", "fired_at": "2026-09-16T12:00:05Z",
              "finished_at": "2026-09-16T12:31:00Z", "session_id": "s1"}
        out = self.run_checks("window", "--trigger-json", self.triggers(ok), "--name-prefix", "daily",
                              "--runs-row", "present", "--now", "2026-09-16T20:00:00Z")
        self.assertFalse(out["dark"])
        self.assertEqual(out["dark_reasons"], [])
        self.assertEqual(out["lifetime_seconds"], 1855.0)
        self.assertEqual(out["last_run"]["session_id"], "s1")

        out = self.run_checks("window", "--trigger-json", self.triggers(ok, wrap=False), "--name-prefix",
                              "daily", "--runs-row", "absent", "--now", "2026-09-17T13:00:00Z")
        self.assertTrue(out["dark"])
        self.assertEqual(out["dark_reasons"], ["fired_at more than 24 h ago", "runs row absent"])

        failed = dict(ok, status="FAILED", finished_at="2026-09-16T12:00:20Z")
        out = self.run_checks("window", "--trigger-json", self.triggers(failed), "--name-prefix", "daily",
                              "--runs-row", "present", "--now", "2026-09-16T13:00:00Z")
        self.assertEqual(out["dark_reasons"], ["last_run status FAILED", "lifetime under 60.0 s"])

    def test_prefix_must_match_exactly_one(self):
        out = self.run_checks("window", "--trigger-json", self.triggers({}), "--name-prefix", "weekly",
                              "--runs-row", "present", want=3)
        self.assertIn("found 0", out["reason"])
        dup = [{"id": "trig_3", "name": "daily 12:00 v1", "last_run": None}]
        out = self.run_checks("window", "--trigger-json", self.triggers({}, extra=dup), "--name-prefix",
                              "daily", "--runs-row", "present", want=3)
        self.assertIn("found 2", out["reason"])


# ---------------------------------------------------------------------------
class Hygiene(Base):
    def test_patterns_scope_exemptions_and_status_line(self):
        doc = self.write("doc.md", "\n".join([
            "# Title",
            "Status: open -- queue/some-row",
            "This was Amended later.",
            "decided (Examplename, 2026-09-01)",
            "at 2026-09-14T21:0xZ and 12:07Z",
            "THREE CAPS WORDS here",
            "clean line",
        ]) + "\n")
        prompt = self.write("prompt.txt", "SHOUTING WORDS FINE HERE\nper Examplename's word\n")
        out = self.run_checks("hygiene", "--doc", doc, "--prompt", prompt, "--operator", "Examplename")
        got = sorted((os.path.basename(h["file"]), h["line"], h["pattern"]) for h in out["hits"])
        self.assertEqual(got, [("doc.md", 3, 1), ("doc.md", 4, 2), ("doc.md", 5, 3), ("doc.md", 6, 4),
                               ("prompt.txt", 2, 2)])
        self.assertEqual(out["status_line"], {doc: True})
        self.assertEqual(out["counts"], {doc: 4, prompt: 1})
        self.assertEqual(out["bytes"][prompt], os.path.getsize(prompt))

        out = self.run_checks("hygiene", "--doc", doc, "--operator", "Othername", "--exempt", doc + "=3,4")
        self.assertEqual(sorted(h["pattern"] for h in out["hits"]), [1])
        self.run_checks("hygiene", "--doc", doc, want=64)  # --operator is required


# ---------------------------------------------------------------------------
class Ledger(Base):
    def test_tally(self):
        d = os.path.join(self.tmp, "db")
        self.write("db/runs/a.json", {"id": "a", "version": 1, "data": {"classifier_refusals": 2, "taken": "2026-09-14T12:0xZ"}})
        self.write("db/runs/b.json", {"classifier_refusals": 0, "taken": "2026-09-15T12:05Z"})
        self.write("db/runs/c.json", {"taken": "2026-09-16T12:05Z"})
        self.write("db/runs/d.json", {"classifier_refusals": 5, "taken": "2026-09-01T12:05Z"})
        out = self.run_checks("tally", "--dir", d, "--collection", "runs", "--field", "classifier_refusals")
        self.assertEqual((out["sum"], out["rows"], out["rows_nonzero"], out["rows_missing_field"]), (7, 4, 2, 1))
        self.assertEqual(out["missing_ids"], ["c"])
        out = self.run_checks("tally", "--dir", d, "--collection", "runs", "--field", "classifier_refusals",
                              "--since", "2026-09-10")
        self.assertEqual((out["sum"], out["rows"]), (2, 3))

    def test_queue_age(self):
        d = os.path.join(self.tmp, "db")
        self.write("db/queue/q1.json", {"state": "open", "tier": "owed", "opened": "2026-09-14T21:0xZ"})
        self.write("db/queue/q2.json", {"data": {"state": "open", "tier": "owed", "opened": "2026-09-15T08:00Z"}})
        self.write("db/queue/q3.json", {"state": "closed", "tier": "owed", "opened": "2026-09-01T00:00Z"})
        self.write("db/queue/q4.json", {"state": "open", "tier": "task", "opened": "2026-09-02T00:00Z"})
        out = self.run_checks("queue-age", "--dir", d, "--now", "2026-09-17T00:00:00Z")
        self.assertEqual(out["open_rows"], 2)
        self.assertEqual(out["oldest"], {"id": "q1", "opened": "2026-09-14T21:0xZ", "parsed_as": "date",
                                         "age_days": 3.0})
        out = self.run_checks("queue-age", "--dir", os.path.join(self.tmp, "nope"), want=3)



# ---------------------------------------------------------------------------
class All(Base):
    """`all` runs several checks in one process.

    The property that matters is NOT that it produces plausible output: it is
    that each part equals what the standalone subcommand produces, so the
    consolidation cannot drift into a second implementation of the recipes.
    The other tests here guard the thing consolidation puts at risk -- a part
    that fails must be at least as visible as it is when it has a process and
    an exit code of its own.
    """

    def setUp(self):
        Base.setUp(self)
        self.serve(SURFACE_URL, fixture_bytes("surface.json"))
        self.serve(WITNESS_URL, fixture_bytes("witness-head.jsonl"))
        self.serve(HOME_LIVE, fixture_bytes("homepage.html"))
        self.serve(HOME_REPO, fixture_bytes("homepage.html"))
        self.serve(seal_url("homepage"), fixture_bytes("seals-homepage.json"))
        self.serve(seal_url("witness-reference"), fixture_bytes("seals-witness-reference.json"))
        self.serve(RECORD_URL, fixture_bytes("record.json"))
        self.serve(FRONT_URL, fixture_bytes("front.json"))
        self.serve(NEW_URL, fixture_bytes("new.json"))
        self.prior_dir = os.path.join(self.tmp, "prior")
        os.makedirs(self.prior_dir)
        for fixture, stem in (("prior-route-surface.json", "route-surface"),
                              ("prior-witness-pair.json", "witness-pair"),
                              ("prior-front-map.json", "front-map")):
            with open(os.path.join(self.prior_dir, stem + ".json"), "wb") as fh:
                fh.write(fixture_bytes(fixture))

    def all_args(self, *extra):
        return ("all", "--prior-dir", self.prior_dir, "--witness-url", WITNESS_URL,
                "--now", "2026-09-17T12:00:00Z") + extra

    def test_every_part_equals_its_standalone_subcommand(self):
        out = self.run_checks(*self.all_args("--seal-label", "homepage"))
        self.assertEqual(out["parts_could_not_run"], [])
        cases = [
            ("surface", ("surface", "--prior", os.path.join(self.prior_dir, "route-surface.json"))),
            ("witness", ("witness", "--prior", os.path.join(self.prior_dir, "witness-pair.json"),
                         "--url", WITNESS_URL)),
            ("front", ("front", "--prior", os.path.join(self.prior_dir, "front-map.json"))),
            ("homepage", ("homepage",)),
            ("bindings", ("bindings",)),
            ("seal:homepage", ("seal", "--label", "homepage")),
        ]
        for name, argv in cases:
            alone = self.run_checks(*(argv + ("--now", "2026-09-17T12:00:00Z")))
            mine = dict(out["parts"][name])
            for key in ("check", "version", "inputs", "status", "reason"):
                alone.pop(key, None)
                mine.pop(key, None)
            self.assertEqual(mine, alone, "part %s differs from the standalone check" % name)

    def test_a_part_that_fails_degrades_the_whole_and_is_named(self):
        # Everything is served except one seal label, so exactly one part fails.
        out = self.run_checks(*self.all_args("--seal-label", "homepage",
                                             "--seal-label", "absent-label"),
                              status="degraded")
        self.assertEqual(out["parts_could_not_run"], ["seal:absent-label"])
        self.assertIn("seal:absent-label", out["reason"])
        self.assertEqual(out["parts"]["seal:absent-label"]["status"], "could_not_run")
        # and the parts around it still ran and are still reported
        self.assertIn("surface", out["parts_ran"])
        self.assertEqual(out["parts"]["seal:homepage"]["status"], "ok")

    def test_skipped_is_not_failed(self):
        out = self.run_checks(*self.all_args("--seal-label", "homepage"))
        self.assertEqual(out["status"], "ok")
        self.assertEqual(out["parts_could_not_run"], [])
        # A part nobody supplied inputs for is named, with its reason, and is
        # absent from both the ran and the failed list.
        for name in ("hashes", "model", "window"):
            self.assertIn(name, out["parts_skipped"])
            self.assertNotIn(name, out["parts_ran"])
            self.assertNotIn(name, out["parts_could_not_run"])
            self.assertNotIn(name, out["parts"])
        self.assertEqual(out["parts_skipped"]["model"], "needs --configured and --record")

    def test_skip_drops_every_label_of_a_part_and_an_unknown_name_is_usage(self):
        out = self.run_checks(*self.all_args("--seal-label", "homepage",
                                             "--seal-label", "witness-reference",
                                             "--skip", "seal", "--skip", "front"))
        self.assertEqual(out["parts_skipped"]["seal:homepage"], "--skip")
        self.assertEqual(out["parts_skipped"]["seal:witness-reference"], "--skip")
        self.assertEqual(out["parts_skipped"]["front"], "--skip")
        self.assertNotIn("front", out["parts"])
        self.run_checks(*self.all_args("--skip", "nonesuch"), want=64)

    def test_model_and_window_run_when_their_inputs_are_given(self):
        trigger = self.write("triggers.json", [{
            "id": "trig_x", "name": "1F916 evening reply check", "cron_expression": "0 23 * * *",
            "enabled": True, "next_run_at": "2026-09-18T23:00:00Z",
            "last_run": {"status": "ROUTINE_RUN_STATUS_SUCCEEDED",
                         "fired_at": "2026-09-16T23:09:00Z",
                         "finished_at": "2026-09-16T23:22:00Z"}}])
        record = self.write("record-model.json", {"model": "claude-opus-5"})
        out = self.run_checks(*self.all_args(
            "--seal-label", "homepage",
            "--configured", "claude-opus-5", "--record", record,
            "--trigger-json", trigger, "--name-prefix", "1F916 evening reply check",
            "--runs-row", "present"))
        self.assertIn("model", out["parts_ran"])
        self.assertIn("window", out["parts_ran"])
        self.assertEqual(out["parts_skipped"], {"hashes": "no --url NAME=URL given"})

    def test_bindings_keeps_the_longer_timeout_it_sets_for_itself(self):
        # cmd_bindings reads /api/record, which has been measured at 40-47 s.
        # Sharing one Ctx across parts would hand it the 30 s default and make
        # it never run; this pins the override to the subparser's own default
        # so the two cannot drift apart unnoticed.
        mod = load_module()
        args = mod.build_parser().parse_args(["bindings"])
        self.assertEqual(mod.ALL_PART_TIMEOUT["bindings"], args.timeout)
        self.assertNotEqual(args.timeout, mod.build_parser().parse_args(["surface"]).timeout)


    def test_one_call_fetches_what_the_separate_calls_would(self):
        out = self.run_checks(*self.all_args("--seal-label", "homepage"))
        urls = [rec["url"] for rec in out["inputs"]["urls"]]
        self.assertIn(SURFACE_URL, urls)
        self.assertIn(WITNESS_URL, urls)
        self.assertIn(RECORD_URL, urls)
        # every fetch recorded a status and a digest, so the caller can audit
        # what one consolidated call actually touched
        for rec in out["inputs"]["urls"]:
            self.assertEqual(rec["status"], 200)
            self.assertTrue(re.match(r"^[0-9a-f]{64}$", rec["sha256"]))





# ---------------------------------------------------------------------------
class RunsRow(Base):
    """`runs-row` transcribes check output into the runs row's field names.

    The risk this command carries is not that it crashes: it is that it writes
    a row that LOOKS right. So the tests below check it against the shape of a
    real row (2026-09-20, read from the ledger), and check that it never fills
    a judgement field, never emits a block for a part that did not run, and
    keeps the row clear of this program's own keys.
    """

    # Read off runs/2026-09-20T12-daily. Split into what a check can produce
    # and what only the run can say.
    REAL_ROW_BLOCKS = {
        "surface": (("capability_sha256", "count", "hash", "prior_count",
                     "prior_route_sha256"), ("change",)),
        "witness": (("fresh", "n", "newest_at", "prefix_hash", "refused"), ()),
        "homepage": (("agree", "live", "repo", "seal", "seal_id"), ("check_id",)),
        "bindings": (("active_keys", "all_verified", "domains", "not_verified",
                      "rows", "thumbprint_ok"), ("note",)),
        "model_check": (("action", "configured", "equal", "record_model"),
                        ("instrument",)),
        "previous_window": (("dark", "dark_reasons", "finished_at", "fired_at",
                             "last_run_status", "lifetime_seconds", "runs_row",
                             "task"), ()),
        "front": (("board_total", "limit", "pinned", "pinned_extra", "pins_added",
                   "pins_removed", "rows", "top_deltas"),
                  ("comments_read_in_full", "delta_note", "filed_from_discovery",
                   "filed_from_discovery_why", "read_in_full")),
    }

    def setUp(self):
        Base.setUp(self)
        self.all_path = self.write("all.json", fixture_bytes("all-output.json"))

    def test_it_produces_every_mechanical_field_a_real_row_carries(self):
        out = self.run_checks("runs-row", "--all", self.all_path)
        for block, (mechanical, judgement) in self.REAL_ROW_BLOCKS.items():
            self.assertIn(block, out["row"], "block %s missing" % block)
            got = out["row"][block]
            for field in mechanical:
                self.assertIn(field, got, "%s.%s is not produced" % (block, field))
            # and it does not quietly fill in the ones that are not its business
            for field in judgement:
                self.assertNotIn(field, got, "%s.%s was invented" % (block, field))

    def test_a_part_that_did_not_run_leaves_no_block_at_all(self):
        payload = fixture_json("all-output.json")
        payload["parts"]["surface"] = {"status": "could_not_run", "reason": "fetch failed: nope"}
        payload["parts_ran"].remove("surface")
        payload["parts_could_not_run"] = ["surface"]
        path = self.write("degraded.json", payload)
        out = self.run_checks("runs-row", "--all", path)
        # not a block of nulls, which would read as measurements of zero
        self.assertNotIn("surface", out["row"])
        self.assertIn("surface", out["blocks_absent"])
        self.assertIn("fetch failed", out["blocks_absent"]["surface"])
        self.assertIn("witness", out["row"])

    def test_judgement_is_merged_and_what_is_missing_is_named(self):
        out = self.run_checks("runs-row", "--all", self.all_path)
        self.assertIn("note", out["judgement_missing"])
        self.assertIn("surface.change", out["judgement_missing"])
        self.assertIsNone(out["row"].get("note"))

        judgement = self.write("j.json", {
            "note": "a sentence only the run can write",
            "kind": "daily",
            "surface": {"change": "two routes added"},
            "front": {"delta_note": "one row"},
        })
        out = self.run_checks("runs-row", "--all", self.all_path, "--judgement", judgement)
        self.assertEqual(out["row"]["note"], "a sentence only the run can write")
        self.assertEqual(out["row"]["surface"]["change"], "two routes added")
        # the merge is deep: the mechanical fields of that block survive it
        self.assertIn("capability_sha256", out["row"]["surface"])
        self.assertNotIn("note", out["judgement_missing"])
        self.assertNotIn("surface.change", out["judgement_missing"])
        self.assertEqual(out["judgement_applied"], ["front", "kind", "note", "surface"])

    def test_the_row_is_nested_so_its_fields_cannot_collide_with_ours(self):
        # A row legitimately carries a field called `note`; this program emits
        # `status` and `reason` of its own. Nesting is what keeps a judgement
        # field from overwriting the envelope that says whether this even ran.
        judgement = self.write("j.json", {"status": "invented", "check": "invented",
                                          "version": 99, "reason": "invented"})
        out = self.run_checks("runs-row", "--all", self.all_path, "--judgement", judgement)
        self.assertEqual(out["status"], "ok")
        self.assertEqual(out["check"], "runs-row")
        self.assertEqual(out["version"], 1)
        self.assertEqual(out["row"]["status"], "invented")

    def test_witness_keeps_the_bucket_a_boolean_would_lose(self):
        out = self.run_checks("runs-row", "--all", self.all_path)
        witness = out["row"]["witness"]
        self.assertEqual(witness["freshness"], "STALE")
        self.assertIs(witness["fresh"], False)
        # LATE is a non-alarm and STALE is not; `fresh` alone cannot say which
        payload = fixture_json("all-output.json")
        payload["parts"]["witness"]["freshness"] = "LATE"
        path = self.write("late.json", payload)
        out = self.run_checks("runs-row", "--all", path)
        self.assertIs(out["row"]["witness"]["fresh"], False)
        self.assertEqual(out["row"]["witness"]["freshness"], "LATE")

    def test_a_judgement_may_not_overwrite_a_measured_field(self):
        # Finding 3 of the 2026-09-20 review, in code shipped the same day.
        # The caller is a scheduled run; before the guard, a judgement file
        # carrying {"homepage": {"agree": true}} replaced a MEASURED value and
        # left no trace, because judgement_applied names top-level keys only.
        judgement = self.write("j.json", {"homepage": {"agree": True}})
        err = self.run_checks("runs-row", "--all", self.all_path,
                              "--judgement", judgement, want=3)
        self.assertIn("homepage.agree", json.dumps(err))

    def test_the_guard_covers_derived_fields_too(self):
        # witness.fresh is the review's own second example and it is NOT in
        # RUNS_ROW_MAP -- the builder derives it from the freshness bucket
        # after the block is built. A guard that only knew the map would have
        # let exactly the named case through.
        judgement = self.write("j.json", {"witness": {"fresh": True}})
        err = self.run_checks("runs-row", "--all", self.all_path,
                              "--judgement", judgement, want=3)
        self.assertIn("witness.fresh", json.dumps(err))

    def test_replacing_a_whole_block_is_caught_as_every_field_in_it(self):
        judgement = self.write("j.json", {"surface": "all fine"})
        err = self.run_checks("runs-row", "--all", self.all_path,
                              "--judgement", judgement, want=3)
        blob = json.dumps(err)
        self.assertIn("surface.count", blob)
        self.assertIn("surface.hash", blob)

    def test_a_field_the_run_is_meant_to_write_is_not_a_collision(self):
        # The other half, and without it the guard would be a refusal machine:
        # DAILY_JUDGEMENT_NESTED is this file's own list of fields the RUN
        # writes, so a judgement carrying one is doing its job -- including
        # previous_window.task, which the builder also derives when the window
        # part ran.
        judgement = self.write("j.json", {
            "surface": {"change": "two routes added"},
            "previous_window": {"task": "1F916 evening (trig_x)"},
            "note": "a sentence only the run can write",
        })
        out = self.run_checks("runs-row", "--all", self.all_path,
                              "--judgement", judgement)
        self.assertEqual(out["row"]["surface"]["change"], "two routes added")
        self.assertEqual(out["row"]["previous_window"]["task"],
                         "1F916 evening (trig_x)")
        self.assertIn("capability_sha256", out["row"]["surface"])

    def test_a_block_that_did_not_run_leaves_the_judgement_free_to_write_it(self):
        # No measurement, no collision: when the part could not run the row
        # carries no block for it, and the run may say what it knows.
        payload = fixture_json("all-output.json")
        payload["parts"]["homepage"] = {"status": "could_not_run",
                                        "reason": "fetch failed: nope"}
        path = self.write("degraded.json", payload)
        out = self.run_checks("runs-row", "--all", path,
                              "--judgement", self.write("j.json",
                                                        {"homepage": {"agree": False}}))
        self.assertIs(out["row"]["homepage"]["agree"], False)
        self.assertIn("homepage", out["blocks_absent"])

    def test_an_all_output_of_the_wrong_shape_is_could_not_run(self):
        path = self.write("nope.json", {"no": "parts here"})
        self.run_checks("runs-row", "--all", path, want=3)



# ---------------------------------------------------------------------------
class PromptIntegrity(Base):
    """`prompt-integrity` holds each stored prompt against its `prompts` row.

    Every case below is a defect that actually occurred in this project's
    ledger between 2026-09-17 and 2026-09-20, plus the one the command is
    honestly unable to catch. The separation under test is not match-versus-
    mismatch: it is RECORD-wrong versus PROMPT-wrong, because collapsing the
    two turns a typing slip into evidence of tampering.
    """

    GOOD = "2bd8eb4f7ad9e668f31b9ae84d6c05f4440f083a7b0fe2eded0303ddadc71516"

    def setUp(self):
        Base.setUp(self)
        self.prompt = "a stored prompt, standing in for 34 KB of one\n"
        self.body = self.prompt.encode("utf-8")
        self.sha = hashlib.sha256(self.body).hexdigest()
        self.triggers = self.write("trig.json", {"data": [
            {"id": "trig_A", "name": "daily", "derived_state": {"prompt": self.prompt}},
            {"id": "trig_NOPROMPT", "name": "no prompt", "derived_state": {}},
        ]})

    def ledger(self, row):
        self.write("db/prompts/trig_A.json", row)
        return os.path.join(self.tmp, "db")

    def verdict(self, row, **kw):
        out = self.run_checks("prompt-integrity", "--trigger-json", self.triggers,
                              "--dir", self.ledger(row), **kw)
        entry = [r for r in out["results"] if r["id"] == "trig_A"][0]
        return out, entry

    def test_a_correct_row_matches(self):
        out, entry = self.verdict({"bytes": len(self.body), "sha256": self.sha})
        self.assertEqual(entry["verdict"], "match")
        self.assertEqual(out["match"], ["trig_A"])
        self.assertEqual(out["mismatch"], [])
        self.assertEqual(out["row_malformed"], [])

    def test_a_truncated_digest_is_the_record_wrong_not_the_prompt(self):
        # The 2026-09-17 and 2026-09-20 defects: sha256 written 16 chars long.
        out, entry = self.verdict({"bytes": len(self.body), "sha256": self.sha[:16]})
        self.assertEqual(entry["verdict"], "row_malformed")
        self.assertIn("64 lowercase hex", entry["detail"])
        self.assertEqual(out["mismatch"], [], "a short digest must never read as tampering")

    def test_a_character_count_recorded_as_bytes_is_the_record_wrong(self):
        # Digest right, byte count wrong: the chars-counted-as-bytes slip.
        out, entry = self.verdict({"bytes": len(self.prompt) - 3, "sha256": self.sha})
        self.assertEqual(entry["verdict"], "row_malformed")
        self.assertIn("bytes disagree", entry["detail"])
        self.assertEqual(out["mismatch"], [])

    def test_a_row_with_no_digest_at_all_is_malformed(self):
        out, entry = self.verdict({"bytes": len(self.body)})
        self.assertEqual(entry["verdict"], "row_malformed")

    def test_a_genuinely_changed_prompt_is_a_mismatch(self):
        out, entry = self.verdict({"bytes": len(self.body), "sha256": self.GOOD})
        self.assertEqual(entry["verdict"], "mismatch")
        self.assertEqual(out["mismatch"], ["trig_A"])

    def test_the_limit_is_real_and_is_under_test(self):
        """A well-formed wrong digest reads as tampering, and cannot not.

        This is the command's honest boundary, asserted rather than hoped for:
        a digest invented at full length is byte-for-byte the same evidence as
        a prompt edited outside the batch. Detection cannot separate them; only
        deriving the value at write time avoids the question.
        """
        invented = "0" * 64
        out, entry = self.verdict({"bytes": len(self.body), "sha256": invented})
        self.assertEqual(entry["verdict"], "mismatch")
        # identical verdict to the genuine-tampering case above
        _, real = self.verdict({"bytes": len(self.body), "sha256": self.GOOD})
        self.assertEqual(entry["verdict"], real["verdict"])

    def test_emit_rows_round_trips_into_a_matching_row(self):
        # The derive half: what it emits, written back, must verify clean.
        out = self.run_checks("prompt-integrity", "--trigger-json", self.triggers,
                              "--emit-rows")
        emitted = out["emit_rows"]["trig_A"]
        self.assertEqual(emitted["sha256"], self.sha)
        self.assertTrue(re.fullmatch(r"[0-9a-f]{64}", emitted["sha256"]))
        _, entry = self.verdict(emitted)
        self.assertEqual(entry["verdict"], "match")

    def test_a_trigger_with_no_row_is_not_a_mismatch_and_only_narrows_it(self):
        out, _ = self.verdict({"bytes": len(self.body), "sha256": self.sha})
        # trig_NOPROMPT carries no prompt and is skipped entirely
        self.assertEqual([r["id"] for r in out["results"]], ["trig_A"])
        # a prompt with no row is its own bucket, never a mismatch
        self.write("db2/prompts/other.json", {"bytes": 1, "sha256": "a" * 64})
        out = self.run_checks("prompt-integrity", "--trigger-json", self.triggers,
                              "--dir", os.path.join(self.tmp, "db2"))
        self.assertEqual(out["row_missing"], ["trig_A"])
        self.assertEqual(out["mismatch"], [])

    def test_without_a_dir_it_measures_and_compares_nothing(self):
        out = self.run_checks("prompt-integrity", "--trigger-json", self.triggers)
        self.assertEqual(out["not_compared"], ["trig_A"])
        entry = out["results"][0]
        self.assertEqual(entry["live_sha256"], self.sha)
        self.assertIsNone(entry["row_sha256"])

    def test_a_trigger_payload_of_the_wrong_shape_is_could_not_run(self):
        bad = self.write("bad.json", {"no": "data list"})
        self.run_checks("prompt-integrity", "--trigger-json", bad, want=3)


# ---------------------------------------------------------------------------
class SubparserDefaults(unittest.TestCase):
    """A default set on one subcommand stays on that subcommand.

    Until 2026-09-20 every subcommand shared one parent parser. `parents=`
    copies action objects by REFERENCE, and set_defaults rewrites the default
    on the action it finds -- so bindings raising its own timeout to 120 s
    raised it for all seventeen checks, four times the documented 30 s, and
    nothing said so. This is the regression test that was missing.
    """

    def test_only_bindings_carries_the_long_timeout(self):
        # Deliberately independent of anything `all` defines, so it measures the
        # parser and would run against any version of this file.
        mod = load_module()
        documented = 30.0
        long_one = mod.build_parser().parse_args(["bindings"]).timeout
        self.assertGreater(long_one, documented)
        for sub, extra in (("surface", []), ("front", []), ("homepage", []),
                           ("seal", ["--label", "homepage"]),
                           ("hashes", ["--url", "a=https://example.invalid/"]),
                           ("witness", ["--url", "https://example.invalid/w.jsonl"])):
            got = mod.build_parser().parse_args([sub] + extra).timeout
            self.assertEqual(got, documented,
                             "%s should default to %s, got %s" % (sub, documented, got))

    def test_an_explicit_timeout_still_wins_everywhere(self):
        mod = load_module()
        for sub in ("surface", "bindings"):
            args = mod.build_parser().parse_args([sub, "--timeout", "7.5"])
            self.assertEqual(args.timeout, 7.5)


if __name__ == "__main__":
    unittest.main()
