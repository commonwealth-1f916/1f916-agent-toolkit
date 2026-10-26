"""tests/test_checks_colony_session.py -- colony/colony_session.py against a fake client.

No key and no network: the same stand-in `colony_sdk` as tests/test_checks_colony.py,
with create_post added, so every rule of the sitting's write path is exercised
against threads built here (queue/task-2026-10-26-sitting-posting-instructions).
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
SCRIPT = os.path.join(HERE, "..", "colony", "colony_session.py")
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
        self.tamper = FakeClient.tamper
        FakeClient.instances.append(self)

    def _raw_request(self, method, path, body=None):
        assert method == "GET"
        mine = [i for i in sorted(self.public)]
        if path.startswith("/posts?author_id="):
            return {"items": [{"id": i} for i in mine if i.startswith("p")], "has_more": False}
        return {"items": [{"id": i} for i in mine if not i.startswith("p")], "has_more": False}

    def get_all_comments(self, pid):
        return self.threads[pid]

    def get_post(self, pid):
        return self.posts[pid]

    def create_comment(self, pid, body, parent_id=None, idempotency_key=None):
        cid = "new-%d" % len(self.writes)
        self.writes.append(("comment", pid, parent_id, idempotency_key))
        stored = body + ("x" if self.tamper else "")
        self.threads[pid].append({"id": cid, "post_id": pid, "parent_id": parent_id,
                                  "body": stored, "author": US, "created_at": "2026-10-26T00:00:00Z"})
        return {"id": cid}

    def get_comment(self, cid):
        for t in self.threads.values():
            for x in t:
                if x["id"] == cid:
                    return x
        return {}

    def create_post(self, title, body, colony=None, post_type="discussion", tags=None, metadata=None,
                    idempotency_key=None):
        assert colony is not None
        pid = "pnew-%d" % len(self.writes)
        self.writes.append(("post", colony, post_type, metadata, idempotency_key))
        self.posts[pid] = {"id": pid, "title": title, "body": body, "colony_name": colony,
                           "colony_id": "uuid-" + colony, "post_type": post_type, "author": US,
                           "created_at": "2026-10-26T00:00:00Z"}
        return {"id": pid}

    def vote_comment(self, cid, value, idempotency_key=None):
        self.writes.append(("vote_comment", cid, value, idempotency_key))

    def vote_post(self, pid, value, idempotency_key=None):
        self.writes.append(("vote_post", pid, value, idempotency_key))


def load_script():
    fake = types.ModuleType("colony_sdk")
    fake.ColonyClient = FakeClient
    sys.modules["colony_sdk"] = fake
    sys.modules.pop("colony_reply", None)
    spec = importlib.util.spec_from_file_location("colony_session", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class ColonySession(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mod = load_script()
        FakeClient.instances = []
        FakeClient.tamper = False
        FakeClient.public = {"c-ours-1", "p-ours"}
        # p-ours: our post; someone commented on it, not naming us (the fieldnoterelay case).
        # post-a: someone else's post where we commented.
        # post-x: a thread we have not joined; one comment names us.
        FakeClient.threads = {
            "p-ours": [{"id": "c-on-ours", "parent_id": None, "author": THEM, "body": "see post 59"}],
            "post-a": [
                {"id": "c-ours-1", "parent_id": None, "author": US, "body": "ours"},
                {"id": "c-a-other", "parent_id": None, "author": OTHER, "body": "a remark"},
            ],
            "post-x": [
                {"id": "c-x-plain", "parent_id": None, "author": OTHER, "body": "hello"},
                {"id": "c-x-mention", "parent_id": None, "author": OTHER, "body": "@commonwealth what do you do?"},
            ],
        }
        FakeClient.posts = {"p-ours": {"id": "p-ours", "author": US},
                            "post-a": {"id": "post-a", "author": THEM},
                            "post-x": {"id": "post-x", "author": OTHER}}
        os.environ["COLONY_API_KEY"] = "dummy-not-a-key"

    def run_script(self, drafts, ids=("c-ours-1", "p-ours"), dry=False, approve=()):
        dp = os.path.join(self.tmp, "drafts.json")
        ip = os.path.join(self.tmp, "ids.txt")
        with open(dp, "w") as f:
            json.dump(drafts, f)
        with open(ip, "w") as f:
            f.write("\n".join(ids) + "\n")
        argv = ["colony_session.py", "--drafts", dp, "--ledger-ids", ip] + (["--dry-run"] if dry else [])
        for s in approve:
            argv += ["--approve", s]
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

    def post(self, **kw):
        d = {"kind": "post", "colony": "findings", "title": "A title", "body": "A body",
             "post_type": "discussion"}
        d.update(kw)
        return d

    # replies
    def test_a_reply_on_our_own_post_needs_no_mention(self):
        rc, lines, client = self.run_script([{"kind": "reply", "post_id": "p-ours", "parent_id": "c-on-ours",
                                              "body": "thanks"}])
        self.assertEqual(rc, 0)
        self.assertEqual(lines[0]["status"], "OK")
        self.assertTrue(all(lines[0]["checks"].values()))
        self.assertTrue(client.writes[0][3].startswith("commonwealth-session-"))

    def test_a_reply_in_a_joined_thread_to_any_comment(self):
        rc, lines, _ = self.run_script([{"kind": "reply", "post_id": "post-a", "parent_id": "c-a-other",
                                         "body": "a reply"}])
        self.assertEqual(lines[0]["status"], "OK")

    def test_a_reply_to_a_mention_in_an_unjoined_thread(self):
        rc, lines, _ = self.run_script([{"kind": "reply", "post_id": "post-x", "parent_id": "c-x-mention",
                                         "body": "hello back"}])
        self.assertEqual(lines[0]["status"], "OK")

    def test_a_reply_in_an_unjoined_thread_without_a_mention_is_skipped(self):
        rc, lines, client = self.run_script([{"kind": "reply", "post_id": "post-x", "parent_id": "c-x-plain",
                                              "body": "hi"}])
        self.assertEqual(lines[0]["status"], "SKIP")
        self.assertEqual(client.writes, [])

    def test_never_under_our_own_comment(self):
        rc, lines, _ = self.run_script([{"kind": "reply", "post_id": "post-a", "parent_id": "c-ours-1",
                                         "body": "me again"}])
        self.assertIn("our own", lines[0]["reason"])

    def test_never_twice_under_one_parent(self):
        r = {"kind": "reply", "post_id": "p-ours", "parent_id": "c-on-ours"}
        rc, lines, client = self.run_script([dict(r, body="one"), dict(r, body="two")])
        self.assertEqual([l.get("status") for l in lines[:2]], ["OK", "SKIP"])
        self.assertEqual(len(client.writes), 1)

    # comments
    def test_a_comment_in_a_joined_thread_is_pre_authorized(self):
        rc, lines, _ = self.run_script([{"kind": "comment", "post_id": "post-a", "body": "more"}])
        self.assertEqual(lines[0]["status"], "OK")
        self.assertIsNone(lines[0]["approval_sha256"])

    def test_a_comment_in_an_unjoined_thread_needs_approval(self):
        d = {"kind": "comment", "post_id": "post-x", "body": "joining"}
        rc, lines, client = self.run_script([d])
        self.assertEqual(lines[0]["status"], "NEEDS APPROVAL")
        self.assertEqual(client.writes, [])
        sha = lines[0]["approval_sha256"]
        rc, lines, client = self.run_script([d], approve=[sha])
        self.assertEqual(lines[0]["status"], "OK")
        self.assertEqual(len(client.writes), 1)

    # posts
    def test_a_post_without_approval_writes_nothing_and_prints_the_hash(self):
        rc, lines, client = self.run_script([self.post()], dry=True)
        self.assertEqual(lines[0]["status"], "NEEDS APPROVAL")
        self.assertEqual(lines[0]["approval_sha256"], self.mod.approval_sha256(self.post()))
        self.assertEqual(client.writes, [])

    def test_an_approved_post_is_written_in_its_colony_and_read_back(self):
        sha = self.mod.approval_sha256(self.post())
        rc, lines, client = self.run_script([self.post()], approve=[sha])
        self.assertEqual(rc, 0)
        self.assertEqual(lines[0]["status"], "OK")
        self.assertTrue(all(lines[0]["checks"].values()))
        self.assertEqual(client.writes[0][1], "findings")

    def test_an_approval_binds_the_exact_text(self):
        sha = self.mod.approval_sha256(self.post())
        rc, lines, client = self.run_script([self.post(body="A body.")], approve=[sha])
        self.assertEqual(lines[0]["status"], "NEEDS APPROVAL")
        self.assertEqual(client.writes, [])

    def test_a_post_must_name_its_colony(self):
        d = self.post(colony="")
        rc, lines, client = self.run_script([d], approve=[self.mod.approval_sha256(d)])
        self.assertEqual(lines[0]["status"], "SKIP")
        self.assertIn("colony", lines[0]["reason"])

    def test_a_finding_needs_metadata_and_polls_have_no_path(self):
        f = self.post(post_type="finding")
        p = self.post(post_type="poll")
        rc, lines, client = self.run_script([f], approve=[self.mod.approval_sha256(f)])
        self.assertIn("metadata", lines[0]["reason"])
        rc, lines, client = self.run_script([p], approve=[self.mod.approval_sha256(p)])
        self.assertIn("post_type", lines[0]["reason"])

    def test_one_post_a_run(self):
        rc, lines, client = self.run_script([self.post(), self.post(title="Another")])
        self.assertEqual(rc, 2)
        self.assertEqual(lines[-1]["summary"]["status"], "refused")
        self.assertIsNone(client)

    # upvotes
    def test_upvote_rules(self):
        rc, lines, client = self.run_script([
            {"kind": "upvote", "post_id": "post-x", "comment_id": "c-x-plain"},
            {"kind": "upvote", "post_id": "p-ours"},
            {"kind": "upvote", "post_id": "post-a", "comment_id": "c-ours-1"},
        ])
        self.assertEqual([l.get("status") for l in lines[:3]], ["OK", "SKIP", "SKIP"])
        self.assertEqual(len(client.writes), 1)

    # shared behaviour
    def test_an_unrecorded_public_item_stops_before_any_write(self):
        FakeClient.public = {"c-ours-1", "p-ours", "c-stranger"}
        rc, lines, client = self.run_script([{"kind": "comment", "post_id": "post-a", "body": "x"}])
        self.assertEqual(rc, 3)
        self.assertEqual(lines[-1]["summary"]["unrecorded"], ["c-stranger"])
        self.assertEqual(client.writes, [])

    def test_dry_run_writes_nothing(self):
        rc, lines, client = self.run_script([{"kind": "comment", "post_id": "post-a", "body": "x"}], dry=True)
        self.assertEqual(lines[0]["status"], "WOULD WRITE")
        self.assertEqual(client.writes, [])

    def test_a_read_back_that_differs_fails(self):
        FakeClient.tamper = True
        rc, lines, _ = self.run_script([{"kind": "comment", "post_id": "post-a", "body": "x"}])
        self.assertEqual(rc, 1)
        self.assertEqual(lines[0]["status"], "MISMATCH")

    def test_no_key_is_could_not_run(self):
        os.environ["COLONY_API_KEY"] = ""
        rc, lines, _ = self.run_script([{"kind": "comment", "post_id": "post-a", "body": "x"}])
        self.assertEqual(rc, 3)
        self.assertEqual(lines[-1]["summary"]["status"], "could_not_run")


if __name__ == "__main__":
    unittest.main()
