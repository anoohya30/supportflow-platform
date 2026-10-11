# SupportFlow API container image.
#
# Two stages:
#   1. "builder" installs the Python libraries into /opt/venv
#   2. the final image copies only that folder plus the app code,
#      so build tools never end up in the image we ship.
#
# Build:  docker build -t supportflow:local .
# Run:    docker run --rm --network host -e DATABASE_URL=... supportflow:local

# ---------- Stage 1: install libraries ----------
FROM python:3.13-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install -r requirements.txt

# ---------- Stage 2: the image we ship ----------
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# A dedicated non-root user (the brief: "containers run as non-root").
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY app ./app
COPY migrations ./migrations
COPY alembic.ini .

# Release information shown by GET /version. CI passes the real values.
ARG APP_VERSION=0.0.0-dev
ARG GIT_COMMIT=unknown
ENV APP_VERSION=$APP_VERSION \
    GIT_COMMIT=$GIT_COMMIT

# Numeric user ID so Kubernetes can verify "runAsNonRoot".
USER 10001:10001

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
