"""Application settings, read from environment variables.

Keeping configuration in environment variables (not in code) means the same
container image can run in staging and production-lab with different settings.
"""

import os

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg://supportflow:supportflow@localhost:5432/supportflow",
)

# Release information returned by GET /version and added to every log line.
APP_VERSION = os.getenv("APP_VERSION", "0.1.0-dev")
GIT_COMMIT = os.getenv("GIT_COMMIT", "unknown")

# Maximum seconds the readiness check may wait for the database.
DB_CHECK_TIMEOUT_SECONDS = int(os.getenv("DB_CHECK_TIMEOUT_SECONDS", "2"))

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
