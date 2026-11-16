"""tests/test_checks_colony_mark_read.py -- colony/colony_mark_read.py against a fake client.

No key and no network: a stand-in `colony_sdk` module records every mark, so
the script's one rule is exercised -- it marks read exactly the ids a run
recorded, or, for the attended backlog clear, every unread notification at or
before a time and none after it (queue/prompt-batch-2026-W47 line 1).
"""
import importlib.util
import io
import json
import os
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "colony", "colony_mark_read.py")


def nid(i):
    return "%08x-0000-4000-8000-%012x" % (i, i)


class FakeClient:
    instances = []
    unread = []
    fail = False

    def __init__(self, key, base_url=None, cache_token=None):
        self.marked = []
        self.reads = []
        FakeClient.instances.append(self)

    def get_notifications(self, unread_only=False, limit=50, offset=None):
        assert unread_only
        self.reads.append((limit, offset))
        o = offset or 0
        return {"notifications": FakeClient.unread[o:o + limit]}

    def mark_notifications_read_batch(self, ids):
        if FakeClient.fail:
            raise RuntimeError("server said no")
        assert len(ids) <= 50
        self.marked.extend(ids)

    def __getattr__(self, name):
        raise AssertionError("colony_mark_read called %s, which it must never call" % name)


def load():
    fake = types.ModuleType("colony_sdk")
    fake.ColonyClient = FakeClient
    sys.modules["colony_sdk"] = fake
    spec = importlib.util.spec_from_file_location("colony_mark_read", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class ColonyMarkRead(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mod = load()
        FakeClient.instances = []
        FakeClient.fail = False
        FakeClient.unread = [{"id": nid(i), "created_at": "2026-11-%02dT10:00:00Z" % (1 + i % 15)}
                             for i in range(130)]
        os.environ["COLONY_API_KEY"] = "dummy-not-a-key"

    def run_script(self, *argv):
        old = sys.argv
        sys.argv = ["colony_mark_read.py"] + list(argv)
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                rc = self.mod.main()
        finally:
            sys.argv = old
        lines = [json.loads(l) for l in buf.getvalue().splitlines() if l.strip()]
        return rc, (lines[-1] if lines else None), (FakeClient.instances[-1] if FakeClient.instances else None)

    def summary(self, new):
        p = os.path.join(self.tmp, "summary.txt")
        with open(p, "w") as f:
            f.write("== some report text\n" + json.dumps({"new": new, "could_not_run": []}) + "\n")
        return p

    def test_marks_exactly_the_ids_the_run_reported(self):
        ids = [nid(1), nid(2), nid(3)]
        rc, out, c = self.run_script("--summary", self.summary([{"id": i} for i in ids]))
        self.assertEqual(rc, 0)
        self.assertEqual(c.marked, ids)
        self.assertEqual(out["marked"], 3)
        self.assertEqual(out["ids_sha256"], self.mod.digest(ids))
        self.assertEqual(c.reads, [])

    def test_no_new_notification_marks_nothing_and_is_clean(self):
        rc, out, c = self.run_script("--summary", self.summary([]))
        self.assertEqual((rc, out["marked"], c.marked), (0, 0, []))

    def test_an_entry_without_an_id_marks_nothing(self):
        rc, out, c = self.run_script("--summary", self.summary([{"id": nid(1)}, {"time": "x"}]))
        self.assertEqual(rc, 2)
        self.assertEqual(FakeClient.instances, [])

    def test_more_than_a_page_of_ids_is_refused(self):
        rc, _, _ = self.run_script("--summary", self.summary([{"id": nid(i)} for i in range(101)]))
        self.assertEqual(rc, 2)
        self.assertEqual(FakeClient.instances, [])

    def test_sixty_ids_go_in_two_batches(self):
        ids = [nid(i) for i in range(60)]
        rc, out, c = self.run_script("--summary", self.summary([{"id": i} for i in ids]))
        self.assertEqual((rc, out["marked"]), (0, 60))
        self.assertEqual(c.marked, ids)

    def test_a_refused_mark_is_could_not_run(self):
        FakeClient.fail = True
        rc, out, _ = self.run_script("--summary", self.summary([{"id": nid(1)}]))
        self.assertEqual(rc, 3)
        self.assertEqual(out["marked"], 0)
        self.assertTrue(out["could_not_run"])

    def test_the_backlog_clear_marks_nothing_after_its_time(self):
        rc, out, c = self.run_script("--backlog-up-to", "2026-11-10T10:00:00Z")
        self.assertEqual(rc, 0)
        want = [n["id"] for n in FakeClient.unread if n["created_at"] <= "2026-11-10T10:00:00Z"]
        self.assertEqual(sorted(c.marked), sorted(want))
        self.assertTrue(all(n["created_at"] <= "2026-11-10T10:00:00Z"
                            for n in FakeClient.unread if n["id"] in c.marked))
        self.assertEqual(out["mode"], "backlog")

    def test_a_missing_key_marks_nothing(self):
        del os.environ["COLONY_API_KEY"]
        rc, _, _ = self.run_script("--summary", self.summary([{"id": nid(1)}]))
        self.assertEqual(rc, 3)
        self.assertEqual(FakeClient.instances, [])

    def test_the_key_never_reaches_the_output(self):
        os.environ["COLONY_API_KEY"] = "sekrit-key-value"
        _, out, _ = self.run_script("--summary", self.summary([{"id": nid(1)}]))
        self.assertNotIn("sekrit", json.dumps(out))


if __name__ == "__main__":
    unittest.main()
