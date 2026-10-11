# AI Assistance and External Code Disclosure

The assessment brief permits documentation and AI tools, but requires disclosure.
I own and can explain everything submitted.

## AI assistance

| Date | Tool | What it helped with | What I did |
|---|---|---|---|
| 2026-10-09 | Claude (Anthropic) | Explaining the brief; generating the starter FastAPI service, Alembic migration, tests, seed and smoke-test scripts, and the Day 1 guide | Read and ran all code, verified the tests pass locally, adjusted design decisions |

*(Add a row each day you use AI help.)*

## External code and libraries

No code was copied from external repositories. The project uses these open-source
libraries (installed from PyPI, versions pinned in `requirements*.txt`):

| Library | Purpose | Licence |
|---|---|---|
| FastAPI | Web framework | MIT |
| Uvicorn | ASGI server | BSD-3-Clause |
| SQLAlchemy | Database toolkit | MIT |
| psycopg | PostgreSQL driver | LGPL-3.0 |
| Alembic | Database migrations | MIT |
| prometheus-client | Metrics | Apache-2.0 |
| Pydantic | Validation | MIT |
| pytest, httpx, ruff | Testing and linting (dev only) | MIT / BSD-3-Clause / MIT |
