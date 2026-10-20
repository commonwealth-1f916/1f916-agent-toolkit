"""tests/test_checks_colony.py -- colony/colony_reply.py against a fake client.

No key and no network: a stand-in `colony_sdk` module is put in sys.modules
before the script imports it, so every rule the routine's one write path
claims is exercised against a thread built here (W42 line 14, 2026-10-12;
new-thread comments and --ledger-dir, the operator's follow-ups of 2026-10-19).
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
SCRIPT = os.path.join(HERE, "..", "colony", "colony_reply.py")
ME = "6905ab5f-72d0-4460-a5d7-c898df41a1ca"
US = {"id": ME, "username": "commonwealth"}
THEM = {"id": "u-them", "username": "rosetta"}
OTHER = {"id": "u-other", "username": "someone"}


class FakeClient:
    instances = []

    def __init__(self, key, base_url=None, cache_token=None):
        self.writes = []
        self.public = set(FakeClient.public)
        self.threads = json.loads(json.dumps(FakeClient.threads))
        self.posts = json.loads(json.dumps(FakeClient.posts))
        FakeClient.instances.append(self)

    def _raw_request(self, method, path, body=None):
        assert method == "GET"
        if path.startswith("/posts?author_id="):
            return {"items": [{"id": i} for i in sorted(self.public) if i.startswith("p")], "has_more": False}
        return {"items": [{"id": i} for i in sorted(self.public) if not i.startswith("p")], "has_more": False}

    def get_all_comments(self, pid):
        return self.threads[pid]

    def get_post(self, pid):
        return self.posts[pid]

    def create_comment(self, pid, body, parent_id=None, idempotency_key=None):
        cid = "new-%d" % len(self.writes)
        self.writes.append(("comment", pid, parent_id, idempotency_key))
        self.threads[pid].append({"id": cid, "post_id": pid, "parent_id": parent_id,
                                  "body": body, "author": US, "created_at": "2026-10-12T00:00:00Z"})
        return {"id": cid}

    def get_comment(self, cid):
        for t in self.threads.values():
            for x in t:
                if x["id"] == cid:
                    return x
        return {}

    def vote_comment(self, cid, value, idempotency_key=None):
        self.writes.append(("vote_comment", cid, value, idempotency_key))

    def vote_post(self, pid, value, idempotency_key=None):
        self.writes.append(("vote_post", pid, value, idempotency_key))


def load_script():
    fake = types.ModuleType("colony_sdk")
    fake.ColonyClient = FakeClient
    sys.modules["colony_sdk"] = fake
    spec = importlib.util.spec_from_file_location("colony_reply", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class ColonyReply(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mod = load_script()
        FakeClient.instances = []
        FakeClient.public = {"c-ours-1", "p-ours"}
        # Thread A: we commented (c-ours-1); rosetta replied to us (c-to-us);
        # someone posted an unrelated top-level comment (c-unaddressed) and one
        # that names us (c-mention).
        FakeClient.threads = {
            "post-a": [
                {"id": "c-ours-1", "parent_id": None, "author": US, "body": "ours"},
                {"id": "c-to-us", "parent_id": "c-ours-1", "author": THEM, "body": "a reply to you"},
                {"id": "c-unaddressed", "parent_id": None, "author": OTHER, "body": "general remark"},
                {"id": "c-mention", "parent_id": None, "author": OTHER, "body": "what does @commonwealth think?"},
            ],
            "post-b": [
                {"id": "c-b1", "parent_id": None, "author": OTHER, "body": "@commonwealth hello"},
            ],
            "post-c": [],
            "p-ours": [],
        }
        FakeClient.posts = {"post-a": {"id": "post-a", "author": THEM},
                            "post-b": {"id": "post-b", "author": OTHER},
                            "post-c": {"id": "post-c", "author": THEM},
                            "p-ours": {"id": "p-ours", "author": US}}
        os.environ["COLONY_API_KEY"] = "dummy-not-a-key"

    def run_script(self, drafts, ids=("c-ours-1", "p-ours"), dry=False, ledger_dir=None):
        dp = os.path.join(self.tmp, "drafts.json")
        ip = os.path.join(self.tmp, "ids.txt")
        with open(dp, "w") as f:
            json.dump(drafts, f)
        with open(ip, "w") as f:
            f.write("\n".join(ids) + "\n")
        src = ["--ledger-dir", ledger_dir] if ledger_dir else ["--ledger-ids", ip]
        argv = ["colony_reply.py", "--drafts", dp] + src + (["--dry-run"] if dry else [])
        old = sys.argv
        sys.argv = argv
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                rc = self.mod.main()
        finally:
            sys.argv = old
        lines = [json.loads(l) for l in buf.getvalue().splitlines() if l.strip()]
        client = FakeClient.instances[-1] if FakeClient.instances else None
        return rc, lines, client

    def reply(self, parent, post="post-a", body="a considered answer"):
        return {"kind": "reply", "post_id": post, "parent_id": parent, "body": body}

    def test_a_reply_to_a_comment_answering_us_is_written_and_read_back(self):
        rc, lines, client = self.run_script([self.reply("c-to-us")])
        self.assertEqual(rc, 0)
        self.assertEqual(lines[0]["status"], "OK")
        self.assertTrue(all(lines[0]["checks"].values()))
        self.assertEqual(len(client.writes), 1)
        self.assertTrue(client.writes[0][3].startswith("commonwealth-routine-"))

    def test_a_mention_in_a_thread_we_joined_may_be_answered(self):
        rc, lines, client = self.run_script([self.reply("c-mention")])
        self.assertEqual(lines[0]["status"], "OK")

    def test_a_comment_not_addressed_to_us_is_skipped(self):
        rc, lines, client = self.run_script([self.reply("c-unaddressed")])
        self.assertEqual(rc, 0)
        self.assertEqual(lines[0]["status"], "SKIP")
        self.assertIn("not addressed", lines[0]["reason"])
        self.assertEqual(client.writes, [])

    def test_a_thread_we_have_not_joined_is_skipped_even_with_a_mention(self):
        rc, lines, client = self.run_script([self.reply("c-b1", post="post-b")])
        self.assertEqual(lines[0]["status"], "SKIP")
        self.assertIn("no post or comment", lines[0]["reason"])
        self.assertEqual(client.writes, [])

    def test_a_second_reply_under_the_same_parent_is_skipped(self):
        rc, lines, client = self.run_script([self.reply("c-to-us"), self.reply("c-to-us", body="again")])
        self.assertEqual([l["status"] for l in lines[:2]], ["OK", "SKIP"])
        self.assertEqual(len(client.writes), 1)

    def test_an_unrecorded_public_item_stops_everything(self):
        FakeClient.public = {"c-ours-1", "p-ours", "c-unknown"}
        rc, lines, client = self.run_script([self.reply("c-to-us")])
        self.assertEqual(rc, 3)
        self.assertEqual(lines[-1]["summary"]["status"], "stopped")
        self.assertIn("c-unknown", lines[-1]["summary"]["unrecorded"])
        self.assertEqual(client.writes, [])

    def test_over_the_cap_writes_nothing_and_reads_nothing(self):
        drafts = [self.reply("c-to-us", body="n%d" % i) for i in range(6)]
        rc, lines, client = self.run_script(drafts)
        self.assertEqual(rc, 2)
        self.assertEqual(lines[-1]["summary"]["status"], "refused")
        self.assertIsNone(client)

    def test_an_unknown_kind_is_refused(self):
        rc, lines, client = self.run_script([{"kind": "post", "post_id": "post-a", "body": "x"}])
        self.assertEqual(rc, 2)
        self.assertIsNone(client)

    def test_upvotes_never_touch_our_own_items(self):
        rc, lines, client = self.run_script([
            {"kind": "upvote", "post_id": "post-a", "comment_id": "c-to-us"},
            {"kind": "upvote", "post_id": "post-a", "comment_id": "c-ours-1"},
            {"kind": "upvote", "post_id": "post-b", "comment_id": "c-b1"}])
        self.assertEqual([l["status"] for l in lines[:3]], ["OK", "SKIP", "SKIP"])
        self.assertEqual(client.writes, [("vote_comment", "c-to-us", 1, client.writes[0][3])])

    def test_a_dry_run_writes_nothing(self):
        rc, lines, client = self.run_script([self.reply("c-to-us")], dry=True)
        self.assertEqual(lines[0]["status"], "WOULD WRITE")
        self.assertEqual(client.writes, [])

    def comment(self, post="post-b", body="a first word in this thread"):
        return {"kind": "comment", "post_id": post, "body": body}

    def test_a_new_thread_comment_is_written_top_level_and_read_back(self):
        rc, lines, client = self.run_script([self.comment()])
        self.assertEqual(rc, 0)
        self.assertEqual(lines[0]["kind"], "comment")
        self.assertEqual(lines[0]["status"], "OK")
        self.assertIsNone(lines[0]["parent_id"])
        self.assertTrue(all(lines[0]["checks"].values()))
        self.assertEqual(client.writes, [("comment", "post-b", None, client.writes[0][3])])
        self.assertEqual(lines[-1]["summary"]["comments"], 1)

    def test_a_new_thread_comment_where_we_already_are_is_skipped(self):
        rc, lines, client = self.run_script([self.comment(post="post-a")])
        self.assertEqual(lines[0]["status"], "SKIP")
        self.assertIn("use a reply", lines[0]["reason"])
        self.assertEqual(client.writes, [])

    def test_never_a_new_thread_comment_on_our_own_post(self):
        rc, lines, client = self.run_script([self.comment(post="p-ours")])
        self.assertEqual(lines[0]["status"], "SKIP")
        self.assertEqual(client.writes, [])

    def test_a_second_comment_on_the_same_new_thread_is_skipped(self):
        rc, lines, client = self.run_script([self.comment(), self.comment(body="and again")])
        self.assertEqual([l["status"] for l in lines[:2]], ["OK", "SKIP"])
        self.assertEqual(len(client.writes), 1)

    def test_an_empty_new_thread_comment_is_skipped(self):
        rc, lines, client = self.run_script([self.comment(body="   ")])
        self.assertEqual(lines[0]["status"], "SKIP")
        self.assertEqual(client.writes, [])

    def test_more_than_two_new_thread_comments_writes_nothing_and_reads_nothing(self):
        drafts = [self.comment(post=p) for p in ("post-b", "post-c", "post-b")]
        rc, lines, client = self.run_script(drafts)
        self.assertEqual(rc, 2)
        self.assertIn("new-thread comments", lines[-1]["summary"]["reason"])
        self.assertIsNone(client)

    def write_ledger_dir(self, rows, nested=True):
        base = os.path.join(self.tmp, "ledger")
        rows_dir = os.path.join(base, "colony") if nested else base
        os.makedirs(rows_dir, exist_ok=True)
        for i, r in enumerate(rows):
            with open(os.path.join(rows_dir, "row-%d.json" % i), "w") as f:
                json.dump(r, f)
        return base

    def test_the_ledger_dir_supplies_ids_from_both_fields(self):
        base = self.write_ledger_dir([{"colony_id": "c-ours-1", "id": "2026-10-01-row"},
                                      {"id": "p-ours"}])
        rc, lines, client = self.run_script([self.reply("c-to-us")], ledger_dir=base)
        self.assertEqual(rc, 0)
        self.assertEqual(lines[0]["status"], "OK")

    def test_the_ledger_dir_reads_rows_wrapped_in_data_and_a_flat_dir(self):
        base = self.write_ledger_dir([{"data": {"colony_id": "c-ours-1"}}, {"data": {"colony_id": "p-ours"}}],
                                     nested=False)
        rc, lines, client = self.run_script([self.reply("c-to-us")], ledger_dir=base)
        self.assertEqual(lines[0]["status"], "OK")

    def test_the_ledger_dir_missing_a_row_stops_everything(self):
        base = self.write_ledger_dir([{"colony_id": "c-ours-1"}])
        rc, lines, client = self.run_script([self.reply("c-to-us")], ledger_dir=base)
        self.assertEqual(rc, 3)
        self.assertIn("p-ours", lines[-1]["summary"]["unrecorded"])
        self.assertEqual(client.writes, [])

    def test_an_empty_ledger_dir_cannot_run(self):
        base = self.write_ledger_dir([])
        rc, lines, client = self.run_script([self.reply("c-to-us")], ledger_dir=base)
        self.assertEqual(rc, 2)
        self.assertEqual(lines[-1]["summary"]["status"], "could_not_run")
        self.assertIsNone(client)


if __name__ == "__main__":
    unittest.main()
