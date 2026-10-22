"""Collector contract tests; no Bluetooth hardware or credentials are needed."""
import importlib.util
import io
from pathlib import Path
import unittest
from urllib.error import HTTPError

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


if __name__ == "__main__":
    unittest.main()
