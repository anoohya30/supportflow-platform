"""Smoke test: call every endpoint once and check the response codes.

Works on Windows, Mac and Linux. Reuse it later against staging/production-lab.

Usage:
    python scripts/smoke_test.py                          # local: http://localhost:8000
    python scripts/smoke_test.py --base-url https://staging.example.com
"""

import argparse
import sys

import httpx


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://localhost:8000")
    args = parser.parse_args()

    failures = 0

    def check(name: str, response: httpx.Response, expected: int) -> httpx.Response:
        nonlocal failures
        ok = response.status_code == expected
        failures += 0 if ok else 1
        mark = "PASS" if ok else "FAIL"
        print(f"[{mark}] {name:<38} expected {expected}, got {response.status_code}")
        return response

    with httpx.Client(base_url=args.base_url, timeout=10) as api:
        check("GET  /health/live", api.get("/health/live"), 200)
        check("GET  /health/ready", api.get("/health/ready"), 200)
        version = check("GET  /version", api.get("/version"), 200)
        print(f"       version info: {version.json()}")

        created = check(
            "POST /tickets (valid)",
            api.post(
                "/tickets",
                json={"subject": "Smoke test", "description": "Synthetic", "priority": "low"},
            ),
            201,
        )
        ticket_id = created.json()["id"]
        check(
            "POST /tickets (invalid priority)",
            api.post("/tickets", json={"subject": "x", "description": "y", "priority": "urgent"}),
            422,
        )
        check(f"GET  /tickets/{ticket_id}", api.get(f"/tickets/{ticket_id}"), 200)
        check(
            f"PATCH /tickets/{ticket_id} -> closed",
            api.patch(f"/tickets/{ticket_id}", json={"status": "closed"}),
            200,
        )
        check("GET  /tickets/999999999 (missing)", api.get("/tickets/999999999"), 404)
        page = check("GET  /tickets?limit=5", api.get("/tickets", params={"limit": 5}), 200)
        print(f"       total tickets in database: {page.json()['total']}")
        check("GET  /metrics", api.get("/metrics"), 200)

    print(f"\n{'ALL CHECKS PASSED' if failures == 0 else f'{failures} CHECK(S) FAILED'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
