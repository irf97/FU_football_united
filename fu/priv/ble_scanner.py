"""Spontaan fixed-receiver adapter: mapped iBeacon advertisements -> durable reports.

The radio path needs the optional pinned Bleak dependency and a Linux BLE adapter.
Replay uses the identical decoder and queue without a radio or that dependency.
"""
import argparse
import asyncio
from contextlib import ExitStack, suppress
from datetime import datetime, timezone
import json
import os
import sqlite3
import sys
import time
import uuid

from equipment_collector import ReportOutbox, post_report, prepare_report, validate_endpoint, validate_token


def parse_config(value):
    beacons = value.get("beacons") if isinstance(value, dict) else None
    interval = value.get("report_interval_seconds", 30) if isinstance(value, dict) else None
    if not isinstance(beacons, list) or not 1 <= len(beacons) <= 30:
        raise ValueError("Map between 1 and 30 owned beacons")
    if type(interval) is not int or not 30 <= interval <= 120:
        raise ValueError("Report interval must be between 30 and 120 seconds")
    mapping, assets = {}, set()
    for entry in beacons:
        if not isinstance(entry, dict):
            raise ValueError("A beacon mapping is required")
        try:
            identity = (str(uuid.UUID(entry["uuid"])), entry["major"], entry["minor"])
            beacon = entry["beacon_id"]
        except (ValueError, KeyError, AttributeError, TypeError):
            raise ValueError("Use a valid UUID, major, minor and inventory ID") from None
        if any(type(n) is not int or not 0 <= n <= 65535 for n in identity[1:]):
            raise ValueError("Major and minor must be unsigned 16-bit integers")
        if not isinstance(beacon, str) or not 1 <= len(beacon.encode()) <= 120 or beacon.strip() != beacon:
            raise ValueError("Use a valid inventory beacon ID")
        if identity in mapping or beacon in assets:
            raise ValueError("Each radio identity and inventory ID must be unique")
        mapping[identity] = beacon
        assets.add(beacon)
    return mapping, interval


def resolve_beacon(manufacturer_data, mapping):
    frame = manufacturer_data.get(0x004C)
    if not isinstance(frame, bytes) or len(frame) != 23 or frame[:2] != b"\x02\x15":
        return None
    identity = (str(uuid.UUID(bytes=frame[2:18])), int.from_bytes(frame[18:20], "big"), int.from_bytes(frame[20:22], "big"))
    return mapping.get(identity)


class ObservationSink:
    def __init__(self, mapping, interval, save):
        self.mapping, self.interval, self.save = mapping, interval, save
        self.last = {}

    def observe(self, manufacturer_data, rssi, *, monotonic=None, observed_at=None):
        if type(rssi) is not int or not -127 <= rssi <= 20:
            return
        beacon = resolve_beacon(manufacturer_data, self.mapping)
        tick = time.monotonic() if monotonic is None else monotonic
        if beacon is None or (beacon in self.last and tick - self.last[beacon] < self.interval):
            return
        timestamp = observed_at or datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        report = prepare_report({"beacon_id": beacon, "message_id": str(uuid.uuid4()), "observed_at": timestamp, "rssi": rssi}, now=timestamp)
        self.save(report)  # SQLite FULL commit must finish before marking this sighting handled.
        self.last[beacon] = tick


def replay_line(line, sink):
    if len(line.encode()) > 4096:
        raise ValueError("Oversized replay advertisement")
    value = json.loads(line)
    data = {int(company): bytes.fromhex(payload) for company, payload in value["manufacturer_data"].items()}
    sink.observe(data, value["rssi"], observed_at=value.get("observed_at"))


async def scan(outbox, mapping, interval):
    try:
        from bleak import BleakScanner
    except ImportError:
        raise ValueError("Install the optional scanner requirements for radio operation") from None
    loop = asyncio.get_running_loop()
    failed = loop.create_future()
    sink = ObservationSink(mapping, interval, outbox.enqueue)

    def detected(_device, advertisement):
        if failed.done():
            return
        try:
            sink.observe(advertisement.manufacturer_data, advertisement.rssi)
        except (ValueError, OSError, sqlite3.Error) as error:
            failed.set_exception(error)

    async def deliver():
        while True:
            row = outbox.db.execute("SELECT message_id, payload FROM pending ORDER BY rowid LIMIT 1").fetchone()
            if row:
                report = prepare_report(json.loads(row[1]))
                # Only HTTP runs in a worker; SQLite and scan callbacks share this event loop.
                receipt = await asyncio.to_thread(post_report, outbox.endpoint, outbox.token, report)
                with outbox.db:
                    outbox.db.execute("DELETE FROM pending WHERE message_id = ? AND payload = ?", row)
                print(json.dumps({"accepted": receipt["id"]}), flush=True)
            else:
                await asyncio.sleep(0.25)

    async with BleakScanner(detection_callback=detected):
        worker = asyncio.create_task(deliver())
        try:
            done, _ = await asyncio.wait([worker, failed], return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        finally:
            worker.cancel()
            with suppress(asyncio.CancelledError):
                await worker
            if not failed.done():
                failed.cancel()
            elif not failed.cancelled():
                failed.exception()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--outbox")
    parser.add_argument("--rehearsal", action="store_true")
    parser.add_argument("--replay", help="JSON-lines advertisements; '-' reads stdin")
    parser.add_argument("--dry-run", action="store_true", help="Decode replay without credentials or delivery")
    args = parser.parse_args(argv)
    if args.dry_run and (not args.replay or args.outbox):
        parser.error("--dry-run requires --replay and cannot use --outbox")
    if not args.dry_run and not args.outbox:
        parser.error("Delivery requires --outbox")
    try:
        endpoint = validate_endpoint(args.endpoint, args.rehearsal)
        with open(args.config, encoding="utf-8") as source:
            value = source.read(32769)
        if len(value.encode()) > 32768:
            raise ValueError("Oversized scanner configuration")
        mapping, interval = parse_config(json.loads(value))
        with ExitStack() as stack:
            if args.dry_run:
                sink = ObservationSink(mapping, interval, lambda report: print(json.dumps(report), flush=True))
            else:
                token = validate_token(os.environ.get("FU_EQUIPMENT_TOKEN"))
                outbox = stack.enter_context(ReportOutbox(args.outbox, endpoint, token))
                outbox.drain()
                sink = ObservationSink(mapping, interval, outbox.enqueue)
            if args.replay:
                source = sys.stdin if args.replay == "-" else stack.enter_context(open(args.replay, encoding="utf-8"))
                while True:
                    line = source.readline(4097)
                    if not line:
                        break
                    if line.strip():
                        replay_line(line, sink)
                        if not args.dry_run:
                            outbox.drain()
            else:
                asyncio.run(scan(outbox, mapping, interval))
        return 0
    except KeyboardInterrupt:
        return 0
    except Exception:
        # Scanner, backend and provider errors can contain identifiers or credentials.
        print("Receiver stopped. Pending reports remain in its private outbox. Check clock, radio, mapping and connection before restart.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
