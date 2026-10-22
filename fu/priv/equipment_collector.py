"""Bridge JSON-line observations from a tag scanner/gateway to FU. Python stdlib only.

This program does not perform radio scanning. Supply scanner observations on stdin.
Set FU_EQUIPMENT_TOKEN privately and pass the HTTPS observations endpoint. A scanner
should supply a stable message_id when replaying a previously delivered observation.
"""
import argparse
from datetime import datetime, timezone
import json
import os
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


def post_report(endpoint, token, report, *, opener=None, pause=time.sleep):
    if not isinstance(token, str) or not token.startswith("fu-eq-") or not 20 <= len(token) <= 160 or any(char.isspace() for char in token):
        raise ValueError("A receiver credential is required")
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--rehearsal", action="store_true", help="Allow loopback HTTP only")
    parser.add_argument("--dry-run", action="store_true", help="Validate input and print reports without delivery")
    args = parser.parse_args()
    try:
        endpoint = validate_endpoint(args.endpoint, args.rehearsal)
        while True:
            line = sys.stdin.readline(4097)
            if not line:
                return 0
            if len(line.encode("utf-8")) > 4096:
                raise ValueError("Oversized scanner input")
            if not line.strip():
                continue
            report = prepare_report(json.loads(line))
            receipt = report if args.dry_run else post_report(endpoint, os.environ.get("FU_EQUIPMENT_TOKEN"), report)
            print(json.dumps(receipt, separators=(",", ":")), flush=True)
    except (ValueError, KeyError, TypeError):
        # Do not log scanner payloads or receiver credentials on failure.
        print("Equipment delivery failed. Check the endpoint, credential and timestamped scanner input.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
