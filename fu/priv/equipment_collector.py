"""Bridge JSON-line observations from a tag scanner/gateway to Spontaan. Python stdlib only.

This program does not perform radio scanning. Supply scanner observations on stdin.
Set FU_EQUIPMENT_TOKEN privately and pass the HTTPS observations endpoint. A scanner
should supply a stable message_id when replaying a previously delivered observation.
Use --outbox with a private local SQLite file to retain reports until acceptance.
"""
import argparse
from datetime import datetime, timezone
from contextlib import ExitStack
import hashlib
import json
import os
import sqlite3
import stat
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, HTTPRedirectHandler, build_opener
import uuid


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def validate_endpoint(endpoint, rehearsal=False):
    parsed = urlsplit(endpoint)
    local = parsed.hostname in ("localhost", "127.0.0.1", "::1")
    if not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Use an endpoint without credentials, query or fragment")
    if parsed.path != "/api/equipment/observations":
        raise ValueError("Use the equipment observations endpoint")
    if parsed.scheme != "https" and not (rehearsal and parsed.scheme == "http" and local):
        raise ValueError("HTTPS is required; rehearsal HTTP is limited to loopback")
    return endpoint


def _utc(value):
    if not isinstance(value, str):
        raise ValueError("A UTC timestamp is required")
    value = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if value.utcoffset() is None or value.utcoffset().total_seconds() != 0:
        raise ValueError("A UTC timestamp is required")
    return value.astimezone(timezone.utc).replace(microsecond=0)


def prepare_report(value, now=None):
    if not isinstance(value, dict):
        raise ValueError("An observation object is required")
    at = _utc(now) if now else datetime.now(timezone.utc).replace(microsecond=0)
    beacon = value.get("beacon_id")
    message = value.get("message_id", str(uuid.uuid4()))
    for item in (beacon, message):
        if not isinstance(item, str) or not 1 <= len(item.encode("utf-8")) <= 120 or item.strip() != item:
            raise ValueError("Identifiers must contain 1 to 120 bytes")
    observed = _utc(value["observed_at"]) if "observed_at" in value else at
    if not -5 <= (at - observed).total_seconds() <= 600:
        raise ValueError("Observation is outside the accepted clock window")
    rssi = value.get("rssi")
    if rssi is not None and (type(rssi) is not int or not -127 <= rssi <= 20):
        raise ValueError("RSSI must be an integer between -127 and 20")
    return {"beacon_id": beacon, "message_id": message,
            "observed_at": observed.isoformat().replace("+00:00", "Z"), "rssi": rssi}


def validate_token(token):
    if not isinstance(token, str) or not token.startswith("fu-eq-") or not 20 <= len(token) <= 160 or any(char.isspace() for char in token):
        raise ValueError("A receiver credential is required")
    return token


def post_report(endpoint, token, report, *, opener=None, pause=time.sleep):
    validate_token(token)
    opener = opener or build_opener(NoRedirect())
    data = json.dumps(report, separators=(",", ":"), sort_keys=True).encode("utf-8")
    for attempt in range(3):
        request = Request(endpoint, data=data, method="POST", headers={
            "Authorization": "Bearer " + token, "Content-Type": "application/json", "Accept": "application/json"})
        try:
            with opener.open(request, timeout=5) as response:
                raw = response.read(16_385)
                if len(raw) > 16_384:
                    raise ValueError("Oversized collector receipt")
                receipt = json.loads(raw)
                if not isinstance(receipt, dict) or type(receipt.get("id")) is not int or receipt.get("source") != "receiver_report":
                    raise ValueError("Invalid collector receipt")
                return receipt
        except HTTPError as error:
            status = error.code
            error.close()
            if status not in (429, 500, 502, 503, 504) or attempt == 2:
                raise ValueError(f"Collector delivery rejected (HTTP {status})") from None
        except (URLError, TimeoutError, OSError):
            if attempt == 2:
                raise ValueError("Collector delivery failed after three attempts") from None
        pause(2 ** attempt)


class ReportOutbox:
    """Commit before delivery; retry unchanged after restart. Never store the token.

    Use one private local file per receiver credential and endpoint. This is a
    recovery queue, not an archive: expired or rejected reports stop delivery
    and remain pending for operator review instead of being silently discarded.
    """

    def __init__(self, path, endpoint, token, *, max_reports=1000):
        validate_token(token)
        if type(max_reports) is not int or not 1 <= max_reports <= 1000:
            raise ValueError("The pending-report limit must be between 1 and 1000")
        if os.path.islink(path):
            raise ValueError("Use a private regular outbox file")
        descriptor = os.open(path, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or (os.name == "posix" and (info.st_mode & 0o077 or info.st_uid != os.getuid())):
                raise ValueError("Use a private regular outbox file")
        finally:
            os.close(descriptor)
        self.endpoint, self.token, self.max_reports = endpoint, token, max_reports
        self.db = sqlite3.connect(path, timeout=5)
        try:
            self.db.execute("PRAGMA journal_mode=DELETE")
            self.db.execute("PRAGMA synchronous=FULL")
            with self.db:
                self.db.execute("BEGIN IMMEDIATE")
                self.db.execute("CREATE TABLE IF NOT EXISTS identity (id INTEGER PRIMARY KEY CHECK (id = 1), endpoint TEXT NOT NULL, token_hash TEXT NOT NULL)")
                self.db.execute("CREATE TABLE IF NOT EXISTS pending (message_id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
                binding = (endpoint, hashlib.sha256(token.encode()).hexdigest())
                self.db.execute("INSERT OR IGNORE INTO identity VALUES (1, ?, ?)", binding)
                if self.db.execute("SELECT endpoint, token_hash FROM identity WHERE id = 1").fetchone() != binding:
                    raise ValueError("Outbox belongs to another endpoint or receiver credential")
        except BaseException:
            self.db.close()
            raise

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.db.close()

    def pending_count(self):
        return self.db.execute("SELECT COUNT(*) FROM pending").fetchone()[0]

    def enqueue(self, value, *, now=None):
        report = prepare_report(value, now=now)
        payload = json.dumps(report, separators=(",", ":"), sort_keys=True)
        with self.db:
            self.db.execute("BEGIN IMMEDIATE")
            previous = self.db.execute("SELECT payload FROM pending WHERE message_id = ?", (report["message_id"],)).fetchone()
            if previous:
                if previous[0] != payload:
                    raise ValueError("A pending message ID has a different payload")
            else:
                if self.pending_count() >= self.max_reports:
                    raise ValueError("The outbox is full; preserve upstream input")
                self.db.execute("INSERT INTO pending VALUES (?, ?)", (report["message_id"], payload))
        return report

    def drain(self, *, opener=None, pause=time.sleep, now=None, on_receipt=None):
        delivered = 0
        while True:
            row = self.db.execute("SELECT message_id, payload FROM pending ORDER BY rowid LIMIT 1").fetchone()
            if row is None:
                return delivered
            # Recheck age without changing the original timestamp or message ID.
            report = prepare_report(json.loads(row[1]), now=now)
            receipt = post_report(self.endpoint, self.token, report, opener=opener, pause=pause)
            with self.db:
                self.db.execute("DELETE FROM pending WHERE message_id = ? AND payload = ?", row)
            delivered += 1
            if on_receipt:
                on_receipt(receipt)


def _print_receipt(value):
    print(json.dumps(value, separators=(",", ":")), flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--rehearsal", action="store_true", help="Allow loopback HTTP only")
    parser.add_argument("--dry-run", action="store_true", help="Validate input and print reports without delivery")
    parser.add_argument("--outbox", help="Private SQLite file for restart-safe delivery")
    parser.add_argument("--drain", action="store_true", help="Deliver pending outbox reports and exit without reading stdin")
    args = parser.parse_args(argv)
    if args.drain and not args.outbox:
        parser.error("--drain requires --outbox")
    if args.dry_run and args.outbox:
        parser.error("--dry-run cannot use a delivery outbox")
    try:
        endpoint = validate_endpoint(args.endpoint, args.rehearsal)
        token = None if args.dry_run else validate_token(os.environ.get("FU_EQUIPMENT_TOKEN"))
        with ExitStack() as stack:
            outbox = stack.enter_context(ReportOutbox(args.outbox, endpoint, token)) if args.outbox else None
            if outbox:
                outbox.drain(on_receipt=_print_receipt)
            if args.drain:
                return 0
            while True:
                line = sys.stdin.readline(4097)
                if not line:
                    return 0
                if len(line.encode("utf-8")) > 4096:
                    raise ValueError("Oversized scanner input")
                if not line.strip():
                    continue
                report = prepare_report(json.loads(line))
                if outbox:
                    outbox.enqueue(report)
                    outbox.drain(on_receipt=_print_receipt)
                else:
                    _print_receipt(report if args.dry_run else post_report(endpoint, token, report))
    except (ValueError, KeyError, TypeError, OSError, sqlite3.Error):
        # Do not log scanner payloads or receiver credentials on failure.
        print("Equipment delivery stopped. Keep unacknowledged scanner input and inspect any pending outbox. Check the endpoint, credential and clock before retrying.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
