"""Collector contract tests; no Bluetooth hardware or credentials are needed."""
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("collector", Path(__file__).parents[1] / "priv/equipment_collector.py")
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class CollectorTest(unittest.TestCase):
    def test_reports_keep_only_collector_fields_and_normalize_utc(self):
        report = collector.prepare_report({"beacon_id": "tag-1", "observed_at": "2026-10-22T12:00:00Z", "message_id": "stable-1", "rssi": -60, "zone": "forged", "owner_id": 999}, now="2026-10-22T12:00:05Z")
        self.assertEqual(set(report), {"beacon_id", "observed_at", "message_id", "rssi"})
        self.assertEqual(report["message_id"], "stable-1")
        self.assertEqual(report["observed_at"], "2026-10-22T12:00:00Z")

    def test_invalid_observations_fail_before_delivery(self):
        for change in [{"beacon_id": []}, {"rssi": True}, {"rssi": -999}, {"observed_at": "2026-10-22T12:05:00Z"}, {"observed_at": "2026-10-22T11:00:00Z"}, {"message_id": ""}]:
            with self.assertRaises(ValueError):
                collector.prepare_report({"beacon_id": "tag", "observed_at": "2026-10-22T12:00:00Z", **change}, now="2026-10-22T12:00:00Z")

    def test_transport_requires_tls_or_an_explicit_loopback_rehearsal(self):
        self.assertEqual(collector.validate_endpoint("https://fu.example/api/equipment/observations"), "https://fu.example/api/equipment/observations")
        self.assertEqual(collector.validate_endpoint("http://localhost:4000/api/equipment/observations", rehearsal=True), "http://localhost:4000/api/equipment/observations")
        for url in ["http://fu.example/api/equipment/observations", "https://token@fu.example/api/equipment/observations", "https://fu.example/wrong", "https://fu.example/api/equipment/observations?token=secret"]:
            with self.assertRaises(ValueError):
                collector.validate_endpoint(url, rehearsal=True)

    def test_retries_reuse_the_same_payload_and_idempotency_key(self):
        requests, pauses = [], []

        class Opener:
            def open(self, request, timeout):
                requests.append(request)
                if len(requests) == 1:
                    raise HTTPError(request.full_url, 503, "unavailable", {}, None)
                return io.BytesIO(b'{"id":1,"source":"receiver_report","zone":"Court"}')

        report = {"beacon_id": "tag", "message_id": "stable", "observed_at": "2026-10-22T12:00:00Z", "rssi": -50}
        receipt = collector.post_report("https://fu.example/api/equipment/observations", "fu-eq-synthetic-credential", report, opener=Opener(), pause=pauses.append)
        self.assertEqual(receipt["id"], 1)
        self.assertEqual(len(requests), 2)
        self.assertEqual(requests[0].data, requests[1].data)
        self.assertEqual(pauses, [1])

    def test_redirects_and_auth_failures_are_not_retried(self):
        for status in [302, 401, 404, 409, 422]:
            calls = []

            class Opener:
                def open(self, request, timeout):
                    calls.append(request)
                    raise HTTPError(request.full_url, status, "rejected", {}, None)

            with self.assertRaises(ValueError):
                collector.post_report("https://fu.example/api/equipment/observations", "fu-eq-synthetic-credential", {}, opener=Opener(), pause=lambda _: None)
            self.assertEqual(len(calls), 1)
        self.assertIsNone(collector.NoRedirect().redirect_request(None, None, 302, "", {}, "https://elsewhere.example"))

    def test_transient_delivery_failure_does_not_claim_input_was_saved(self):
        with patch.dict(os.environ, {"FU_EQUIPMENT_TOKEN": "fu-eq-synthetic-credential"}), patch.object(sys, "stdin", io.StringIO('{"beacon_id":"tag"}\n')), patch.object(sys, "stderr", io.StringIO()) as errors, patch.object(collector, "post_report", side_effect=ValueError("offline")):
            self.assertEqual(collector.main(["--endpoint", "https://fu.example/api/equipment/observations"]), 1)
        self.assertIn("unacknowledged scanner input", errors.getvalue())
        self.assertNotIn("reports are retained", errors.getvalue())


class OutboxTest(unittest.TestCase):
    endpoint = "https://fu.example/api/equipment/observations"
    token = "fu-eq-synthetic-credential"
    now = "2026-10-23T10:00:00Z"
    report = {"beacon_id": "tag", "message_id": "stable", "observed_at": now, "rssi": -50}

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "receiver.sqlite3"

    def open_outbox(self, **changes):
        return collector.ReportOutbox(self.path, changes.get("endpoint", self.endpoint), changes.get("token", self.token), max_reports=changes.get("max_reports", 1000))

    def test_failure_retains_committed_report_and_restart_reuses_generated_id(self):
        requests = []

        class FailingOpener:
            def open(self, request, timeout):
                requests.append(request)
                raise OSError("offline")

        with self.open_outbox() as outbox:
            outbox.enqueue({"beacon_id": "tag", "observed_at": self.now, "owner_id": 99}, now=self.now)
            with self.assertRaises(ValueError):
                outbox.drain(opener=FailingOpener(), pause=lambda _: None, now=self.now)
            self.assertEqual(outbox.pending_count(), 1)

        class WorkingOpener:
            def open(self, request, timeout):
                requests.append(request)
                return io.BytesIO(b'{"id":1,"source":"receiver_report"}')

        with self.open_outbox() as restarted:
            self.assertEqual(restarted.drain(opener=WorkingOpener(), now=self.now), 1)
            self.assertEqual(restarted.pending_count(), 0)
        self.assertEqual(len(requests), 4)
        self.assertEqual(len({request.data for request in requests}), 1)
        payload = json.loads(requests[0].data)
        self.assertEqual(set(payload), {"beacon_id", "message_id", "observed_at", "rssi"})
        self.assertTrue(payload["message_id"])
        self.assertNotIn(self.token.encode(), self.path.read_bytes())

    def test_committed_report_survives_abrupt_process_exit(self):
        script = """
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location('collector', sys.argv[1])
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
outbox = collector.ReportOutbox(sys.argv[2], sys.argv[3], sys.argv[4])
outbox.enqueue(json.loads(sys.argv[5]), now=sys.argv[6])
os._exit(23)
"""
        result = subprocess.run([sys.executable, "-c", script, str(Path(collector.__file__)), str(self.path), self.endpoint, self.token, json.dumps(self.report), self.now], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 23, result.stderr)
        with self.open_outbox() as restarted:
            self.assertEqual(restarted.pending_count(), 1)

    def test_identity_binding_rejects_another_endpoint_or_receiver_even_when_empty(self):
        with self.open_outbox():
            pass
        for changes in [{"endpoint": "https://other.example/api/equipment/observations"}, {"token": "fu-eq-other-synthetic-credential"}]:
            with self.assertRaises(ValueError):
                self.open_outbox(**changes)
        with self.open_outbox() as original:
            self.assertEqual(original.pending_count(), 0)

    def test_queue_bound_and_conflicting_duplicate_preserve_existing_payload(self):
        with self.open_outbox(max_reports=1) as outbox:
            outbox.enqueue(self.report, now=self.now)
            outbox.enqueue(self.report, now=self.now)
            for change in [{"message_id": "new"}, {"rssi": -70}]:
                with self.assertRaises(ValueError):
                    outbox.enqueue({**self.report, **change}, now=self.now)
            self.assertEqual(outbox.pending_count(), 1)

    def test_expired_report_is_retained_without_sending_or_refreshing_timestamp(self):
        with self.open_outbox() as outbox:
            outbox.enqueue(self.report, now=self.now)
            with patch.object(collector, "post_report") as post:
                with self.assertRaises(ValueError):
                    outbox.drain(now="2026-10-23T10:10:01Z")
                post.assert_not_called()
            self.assertEqual(outbox.pending_count(), 1)

    def test_invalid_receipt_or_revocation_does_not_remove_pending_report(self):
        class InvalidOpener:
            def open(self, request, timeout):
                return io.BytesIO(b'{"id":1,"source":"manual"}')

        class RevokedOpener:
            def open(self, request, timeout):
                raise HTTPError(request.full_url, 401, "revoked", {}, None)

        with self.open_outbox() as outbox:
            outbox.enqueue(self.report, now=self.now)
            for opener in [InvalidOpener(), RevokedOpener()]:
                with self.assertRaises(ValueError):
                    outbox.drain(opener=opener, now=self.now)
                self.assertEqual(outbox.pending_count(), 1)

    @unittest.skipUnless(os.name == "posix", "POSIX file permissions")
    def test_private_queue_permissions_and_no_symlink_following(self):
        with self.open_outbox():
            pass
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        alias = self.path.with_suffix(".link")
        alias.symlink_to(self.path)
        with self.assertRaises((ValueError, OSError)):
            collector.ReportOutbox(alias, self.endpoint, self.token)
        self.path.chmod(0o644)
        with self.assertRaises(ValueError):
            self.open_outbox()

    def test_real_http_lost_receipt_replays_one_server_record_after_restart(self):
        accepted, requests = {}, []
        responding = threading.Event()

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                payload = self.rfile.read(int(self.headers["Content-Length"]))
                value = json.loads(payload)
                requests.append(payload)
                receipt = accepted.setdefault(value["message_id"], {"id": 1, "source": "receiver_report"})
                if not responding.is_set():
                    self.connection.shutdown(socket.SHUT_RDWR)
                    self.close_connection = True
                    return
                body = json.dumps(receipt).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        endpoint = f"http://127.0.0.1:{server.server_port}/api/equipment/observations"
        try:
            with self.open_outbox(endpoint=endpoint) as outbox:
                outbox.enqueue(self.report, now=self.now)
                with self.assertRaises(ValueError):
                    outbox.drain(pause=lambda _: None, now=self.now)
            responding.set()
            with self.open_outbox(endpoint=endpoint) as restarted:
                self.assertEqual(restarted.drain(now=self.now), 1)
                self.assertEqual(restarted.pending_count(), 0)
            self.assertEqual(len(accepted), 1)
            self.assertEqual(len(requests), 4)
            self.assertEqual(len(set(requests)), 1)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_cli_recovers_pending_before_reading_input_and_sanitizes_failure(self):
        now = collector.datetime.now(collector.timezone.utc).replace(microsecond=0).isoformat()
        with self.open_outbox() as outbox:
            outbox.enqueue({**self.report, "observed_at": now})

        class UnreadableInput:
            def readline(self, *_):
                raise AssertionError("Pending delivery must be recovered before reading new input")

        with patch.dict(os.environ, {"FU_EQUIPMENT_TOKEN": self.token}), patch.object(sys, "stdin", UnreadableInput()), patch.object(sys, "stderr", io.StringIO()) as errors, patch.object(collector, "post_report", side_effect=ValueError("sensitive upstream detail")):
            result = collector.main(["--endpoint", self.endpoint, "--outbox", str(self.path)])
        self.assertEqual(result, 1)
        self.assertNotIn(self.token, errors.getvalue())
        self.assertNotIn("sensitive", errors.getvalue())
        with self.open_outbox() as restarted:
            self.assertEqual(restarted.pending_count(), 1)

    def test_cli_enqueues_before_delivery_and_drain_does_not_read_stdin(self):
        input_report = {"beacon_id": "tag"}

        def fail_after_enqueue(*_, **_options):
            with self.open_outbox() as observer:
                self.assertEqual(observer.pending_count(), 1)
            raise ValueError("offline")

        args = ["--endpoint", self.endpoint, "--outbox", str(self.path)]
        with patch.dict(os.environ, {"FU_EQUIPMENT_TOKEN": self.token}), patch.object(sys, "stdin", io.StringIO(json.dumps(input_report) + "\n")), patch.object(sys, "stderr", io.StringIO()), patch.object(collector, "post_report", side_effect=fail_after_enqueue):
            self.assertEqual(collector.main(args), 1)
        with patch.dict(os.environ, {"FU_EQUIPMENT_TOKEN": self.token}), patch.object(sys, "stdin", None), patch.object(sys, "stdout", io.StringIO()) as output, patch.object(collector, "post_report", return_value={"id": 1, "source": "receiver_report"}):
            self.assertEqual(collector.main(args + ["--drain"]), 0)
        self.assertEqual(json.loads(output.getvalue())["id"], 1)
        with self.open_outbox() as restarted:
            self.assertEqual(restarted.pending_count(), 0)


if __name__ == "__main__":
    unittest.main()
