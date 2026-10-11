"""Insert synthetic (fake) tickets for testing and load tests.

Usage:
    python scripts/seed_tickets.py            # 1000 tickets (brief minimum)
    python scripts/seed_tickets.py --count 5000
"""

import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import func, insert, select  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402

from app.db import engine  # noqa: E402
from app.models import PRIORITIES, STATUSES, Ticket  # noqa: E402

SUBJECTS = [
    "Cannot log in",
    "Invoice missing",
    "App is slow",
    "Password reset email not received",
    "Order not delivered",
    "Wrong item shipped",
    "Refund request",
    "Account locked",
    "Feature request",
    "Error on checkout page",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=1000)
    args = parser.parse_args()

    rng = random.Random(42)  # fixed seed: same data every run, easy to compare
    rows = [
        {
            "subject": f"{rng.choice(SUBJECTS)} #{i}",
            "description": f"Synthetic ticket {i} generated for testing. No real customer data.",
            "priority": rng.choice(PRIORITIES),
            "status": rng.choice(STATUSES),
        }
        for i in range(1, args.count + 1)
    ]

    with Session(engine) as session:
        session.execute(insert(Ticket), rows)
        session.commit()
        total = session.scalar(select(func.count()).select_from(Ticket))

    print(f"Inserted {args.count} tickets. Total tickets in database: {total}")


if __name__ == "__main__":
    main()
