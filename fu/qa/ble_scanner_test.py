import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "priv"))
spec = importlib.util.spec_from_file_location("ble_scanner", Path(__file__).resolve().parents[1] / "priv/ble_scanner.py")
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)

UUID = "25ac0df5-62a7-4a0b-93f4-1e6738d04de1"
FRAME = bytes.fromhex("0215" + UUID.replace("-", "") + "00010002c5")
CONFIG = {"beacons": [{"uuid": UUID, "major": 1, "minor": 2, "beacon_id": "commons-gear-1"}], "report_interval_seconds": 30}


class ScannerContractTest(unittest.TestCase):
    def test_known_ibeacon_resolves_to_inventory_id_without_a_mac_address(self):
        mapping, interval = scanner.parse_config(CONFIG)
        self.assertEqual(interval, 30)
        self.assertEqual(scanner.resolve_beacon({0x004C: FRAME}, mapping), "commons-gear-1")

    def test_unknown_truncated_or_other_manufacturer_is_ignored(self):
        mapping, _ = scanner.parse_config(CONFIG)
        for data in [{}, {0x004C: FRAME[:10]}, {0x1234: FRAME}, {0x004C: bytes(23)}, {0x004C: FRAME[:-3] + b"\x00\x03\xc5"}]:
            self.assertIsNone(scanner.resolve_beacon(data, mapping))

    def test_duplicate_radio_or_inventory_identifiers_are_rejected(self):
        for field in ["uuid", "beacon_id"]:
            other = dict(CONFIG["beacons"][0])
            if field == "uuid":
                other["beacon_id"] = "another-item"
            else:
                other["major"] = 2
            with self.assertRaises(ValueError):
                scanner.parse_config({"beacons": CONFIG["beacons"] + [other]})

    def test_config_bounds_reject_unbounded_or_invalid_values(self):
        for change in [{"beacons": []}, {"report_interval_seconds": 0}, {"report_interval_seconds": True}, {"beacons": [{"uuid": "bad", "major": 1, "minor": 2, "beacon_id": "gear"}]}]:
            with self.assertRaises(ValueError):
                scanner.parse_config(dict(CONFIG, **change))

    def test_observation_is_durable_before_debounce_and_reuses_no_physical_address(self):
        saved = []
        mapping, interval = scanner.parse_config(CONFIG)
        state = scanner.ObservationSink(mapping, interval, saved.append)
        state.observe({0x004C: FRAME}, -58, monotonic=10, observed_at="2026-10-23T15:00:00Z")
        state.observe({0x004C: FRAME}, -60, monotonic=11, observed_at="2026-10-23T15:00:01Z")
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0]["beacon_id"], "commons-gear-1")
        self.assertEqual(saved[0]["observed_at"], "2026-10-23T15:00:00Z")
        self.assertNotIn("address", saved[0])
        state.observe({0x004C: FRAME}, -61, monotonic=40, observed_at="2026-10-23T15:00:30Z")
        self.assertEqual(len(saved), 2)
        self.assertNotEqual(saved[0]["message_id"], saved[1]["message_id"])

    def test_failed_enqueue_is_not_marked_as_handled(self):
        saved = []
        mapping, interval = scanner.parse_config(CONFIG)
        def fail(_):
            raise ValueError("full")
        state = scanner.ObservationSink(mapping, interval, fail)
        with self.assertRaises(ValueError):
            state.observe({0x004C: FRAME}, -58, monotonic=10)
        state.save = saved.append
        state.observe({0x004C: FRAME}, -58, monotonic=11)
        self.assertEqual(len(saved), 1)

    def test_invalid_signal_does_not_create_a_report(self):
        mapping, interval = scanner.parse_config(CONFIG)
        state = scanner.ObservationSink(mapping, interval, lambda _: self.fail("invalid report saved"))
        for rssi in [True, -128, 21, "-58", None]:
            state.observe({0x004C: FRAME}, rssi, monotonic=10)

    def test_replay_format_is_the_same_as_the_native_scanner_callback(self):
        saved = []
        mapping, interval = scanner.parse_config(CONFIG)
        state = scanner.ObservationSink(mapping, interval, saved.append)
        scanner.replay_line(json.dumps({"manufacturer_data": {"76": FRAME.hex()}, "rssi": -58}), state)
        self.assertEqual(saved[0]["beacon_id"], "commons-gear-1")


class ScannerLifecycleTest(unittest.IsolatedAsyncioTestCase):
    async def test_delivery_failure_stops_radio_and_preserves_the_committed_report(self):
        closed = []
        class Radio:
            def __init__(self, detection_callback):
                self.callback = detection_callback
            async def __aenter__(self):
                self.callback(None, SimpleNamespace(manufacturer_data={0x004C: FRAME}, rssi=-58))
                return self
            async def __aexit__(self, *_):
                closed.append(True)
        mapping, interval = scanner.parse_config(CONFIG)
        with tempfile.TemporaryDirectory() as directory:
            with scanner.ReportOutbox(str(Path(directory) / "queue.sqlite"), "https://spontaan.example/api/equipment/observations", "fu-eq-synthetic-scanner-credential") as outbox:
                with patch.dict(sys.modules, {"bleak": SimpleNamespace(BleakScanner=Radio)}), patch.object(scanner, "post_report", side_effect=ValueError("offline")):
                    with self.assertRaises(ValueError):
                        await scanner.scan(outbox, mapping, interval)
                self.assertEqual(outbox.pending_count(), 1)
                self.assertEqual(closed, [True])

    async def test_full_outbox_stops_radio_without_discarding_the_existing_report(self):
        closed = []
        class Radio:
            def __init__(self, detection_callback):
                self.callback = detection_callback
            async def __aenter__(self):
                self.callback(None, SimpleNamespace(manufacturer_data={0x004C: FRAME}, rssi=-58))
                return self
            async def __aexit__(self, *_):
                closed.append(True)
        mapping, interval = scanner.parse_config(CONFIG)
        with tempfile.TemporaryDirectory() as directory:
            with scanner.ReportOutbox(str(Path(directory) / "queue.sqlite"), "https://spontaan.example/api/equipment/observations", "fu-eq-synthetic-scanner-credential", max_reports=1) as outbox:
                outbox.enqueue({"beacon_id": "existing", "message_id": "keep-this-report"})
                with patch.dict(sys.modules, {"bleak": SimpleNamespace(BleakScanner=Radio)}), patch.object(scanner, "post_report", side_effect=ValueError("offline")):
                    with self.assertRaises(ValueError):
                        await scanner.scan(outbox, mapping, interval)
                self.assertEqual(outbox.pending_count(), 1)
                self.assertEqual(outbox.db.execute("SELECT message_id FROM pending").fetchone()[0], "keep-this-report")
                self.assertEqual(closed, [True])


if __name__ == "__main__":
    unittest.main()
