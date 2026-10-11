# Day 1 Guide: Setup and the SupportFlow API

**Goal for today:** by the end of the day you have a GitHub repository with a working
ticket API running on your laptop, connected to a real PostgreSQL database, with
automated tests passing. You also have your AWS account protected by a budget alert.

**Time needed:** about 8 hours. Take breaks between parts.

| Part | What you do | Time |
|---|---|---|
| A | Admin: email the assessors, set up AWS safely | 1 h |
| B | Install the tools | 1 h |
| C | Create the GitHub repository and issues | 30 min |
| D | Write down your design decisions | 30 min |
| E | Add the app code and understand it | 2.5 h |
| F | Run it: database, migration, seed data, API | 1 h |
| G | Run the tests and the linter | 30 min |
| H | Commit, open a pull request, save evidence | 1 h |

> **Tip:** tick the checkboxes in this file as you go. At the end, this file plus
> the files in `docs/evidence/` are your proof of Day 1.

---

## Part A: Admin (1 hour)

### A1. Email SkillAnthem about scope ☐

The brief says the project is 14 days and 60–80 hours. It also says to raise scope
changes **in writing**. Send something like this:

> Subject: DEVOPS 01: timeline and scope confirmation
>
> Hi team, the brief lists a 14-working-day timebox, but I have 5 days to submit.
> Could you confirm the deadline? If 5 days is firm, I plan to deliver the core
> release, monitoring and recovery path, and to mark items such as network-policy
> negative tests, credential rotation and drift demonstrations as "not completed" in
> my evidence matrix. I will be using my own AWS account with a spending cap.
> Thanks, Anoohya

Save their reply. It goes in your evidence later.

### A2. Make your AWS account safe ☐

You must use your **own** AWS account (never an employer's).

1. Sign in to the AWS Console as the root user (the email you signed up with).
2. **Turn on MFA for root:** click your account name (top right) → *Security
   credentials* → *Assign MFA device*. Use an authenticator app on your phone.
3. **Create a budget alert:** search for **Budgets** in the top search bar →
   *Create budget* → *Use a template* → *Monthly cost budget*.
   - Budget amount: something you can afford, e.g. **$20**.
   - Email: your email address.
   - Create it. AWS emails you when spending reaches 85% and 100% of the budget.
4. **Pick one region** and use it for everything, e.g. `eu-west-2` (London) or
   `ap-south-1` (Mumbai). Write it down. You'll need it on Day 3.

> The AWS screen names may look slightly different from these steps. Look for the
> same words.

**Why:** a budget alert stops a forgotten server from surprising you with a bill.
The brief explicitly requires budget alerts.

**Nothing is created in AWS today.** Servers start on Day 3, so today costs nothing.

---

## Part B: Install the tools (1 hour)

Install these today. You only *use* Git, Python, Docker and VS Code today. The rest
are for Days 2–3, but installing now avoids surprises later.

| Tool | Used for | Download |
|---|---|---|
| Git | Version control | https://git-scm.com/downloads |
| Python 3.12 or 3.13 | Running the app | https://www.python.org/downloads/ (Windows: tick **"Add python.exe to PATH"**) |
| Docker Desktop | Running PostgreSQL locally | https://www.docker.com/products/docker-desktop/ |
| VS Code | Editing code | https://code.visualstudio.com/ |
| kubectl | Talking to Kubernetes (Day 2) | https://kubernetes.io/docs/tasks/tools/ |
| k3d | Local Kubernetes cluster (Day 2) | https://k3d.io |
| Helm | Kubernetes packaging (Day 2) | https://helm.sh/docs/intro/install/ |
| Terraform | AWS infrastructure (Day 3) | https://developer.hashicorp.com/terraform/install |
| AWS CLI v2 | AWS from the terminal (Day 3) | https://aws.amazon.com/cli/ |

**Mac shortcut (Homebrew):**
```bash
brew install git python@3.12 kubectl k3d helm awscli
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
brew install --cask docker visual-studio-code
```

### B1. Check everything installed ☐

Open a **new** terminal (on Windows, use PowerShell) and run:

```bash
git --version
python --version        # Mac/Linux may need: python3 --version
docker --version
docker compose version
kubectl version --client
k3d version
helm version
terraform -version
aws --version
```

Each command should print a version number. If one says "not recognized" or
"command not found", reinstall that tool and **open a new terminal**.

Start **Docker Desktop** and wait until it says "Engine running".

---

## Part C: GitHub repository and issues (30 minutes)

The brief requires **Git issues, feature branches and pull requests**. Reviewers
look at this history, so start the habit today.

### C1. Create the repository ☐

1. On GitHub: **New repository** → name `supportflow-platform` → **Public** (good
   for a portfolio) → tick *Add a README* → Create.
2. Clone it to your laptop:
   ```bash
   git clone https://github.com/<your-username>/supportflow-platform.git
   cd supportflow-platform
   ```
3. Tell Git who you are (first time only):
   ```bash
   git config --global user.name "Anoohya Bhairavabatla"
   git config --global user.email "<your-email>"
   ```

### C2. Create issues ☐

On GitHub → **Issues** → **New issue**. Create one issue per piece of work. For now,
create these (you'll add more on later days):

1. `Record design decisions and architecture`
2. `Ticket API: create, read, update status, list`
3. `Health, version and metrics endpoints`
4. `Database migrations and seed data`
5. `Container image and Helm chart` (Day 2)
6. `Terraform: AWS infrastructure` (Day 3)
7. `CI pipeline with security gates` (Day 3)
8. `GitOps deployment with Argo CD` (Day 4)
9. `Monitoring, alerts and backups` (Day 4)
10. `Load test, failure exercises and runbooks` (Day 5)

### C3. Protect the main branch ☐

GitHub → repo **Settings** → **Branches** (or **Rules → Rulesets**) → add a rule for
`main`: *Require a pull request before merging*. This stops you from pushing straight
to `main`, which is what the brief wants.

> On a free personal account, branch protection rules are fully available for
> **public** repositories. This is one reason to make the repo public.

### C4. Create today's feature branch ☐

```bash
git checkout -b feature/2-ticket-api
```

The `2` matches issue #2. All of today's work goes on this branch.

---

## Part D: Design decisions (30 minutes)

The brief says: *"Record design decisions before implementation."*

### D1. Add the decisions file ☐

Copy `docs/decisions.md` from the starter files into your repo. Read every decision
and make sure you can explain it in your own words. Change anything you disagree
with. It's **your** project and you must defend it.

### D2. Add the AI-assistance disclosure ☐

The brief says: *"Disclose assistance and adapted external code."* Copy
`docs/ai-assistance.md` into your repo and keep it honest and up to date.

---

## Part E: The app code (2.5 hours)

### E1. Copy the starter files into your repo ☐

Unzip the starter package and copy **everything** into your `supportflow-platform`
folder (it's fine to overwrite the README). Your folder should now look like this:

```
supportflow-platform/
├── app/                    ← the API code
│   ├── config.py           settings from environment variables
│   ├── db.py               database connection + readiness check
│   ├── models.py           the "tickets" table
│   ├── schemas.py          request/response rules (validation)
│   ├── observability.py    JSON logs + Prometheus metrics
│   └── main.py             the endpoints
├── migrations/             ← database version history (Alembic)
│   └── versions/0001_create_tickets.py
├── tests/                  ← automated tests (19 tests)
├── scripts/
│   ├── seed_tickets.py     inserts 1,000 fake tickets
│   ├── smoke_test.py       calls every endpoint once
│   └── create-test-db.sql  creates the test database
├── docs/                   ← documentation (this guide lives here)
├── infra/ charts/ gitops/ .github/ load-tests/   ← empty for now (Days 2–5)
├── docker-compose.yml      ← local PostgreSQL
├── alembic.ini             ← migration settings
├── pyproject.toml          ← lint + test settings
├── requirements.txt        ← app libraries (exact versions)
├── requirements-dev.txt    ← test/lint tools
├── .env.example            ← example settings (copy to .env)
└── .gitignore              ← files Git must never commit
```

### E2. Understand what you built ☐

**Read each file in `app/` slowly.** The comments explain each part. Here's the
big picture.

#### How a request travels through the app

```
You (curl / browser)
   │  POST /tickets {"subject": "...", "description": "...", "priority": "high"}
   ▼
main.py  → middleware gives the request an ID and starts a timer
   ▼
schemas.py → checks the input. Wrong priority? → automatic 422 error
   ▼
main.py create_ticket() → models.py Ticket → db.py session
   ▼
PostgreSQL saves the row, generates id + created_at
   ▼
main.py → returns 201 + the ticket as JSON
   ▼
middleware → counts the request in /metrics, writes one JSON log line
```

#### The endpoints

| Endpoint | What it does | Success | Errors |
|---|---|---|---|
| `POST /tickets` | Create a ticket | 201 | 422 bad input |
| `GET /tickets/{id}` | Read one ticket | 200 | 404 not found |
| `PATCH /tickets/{id}` | Change status (open / in_progress / closed) | 200 | 404, 422 |
| `GET /tickets?limit=20&offset=0` | List tickets, max 100 per page | 200 | 422 if limit > 100 |
| `GET /health/live` | "Is the process running?" | 200 | — |
| `GET /health/ready` | "Can I reach the database?" | 200 | 503 if DB down |
| `GET /version` | Release version and Git commit | 200 | — |
| `GET /metrics` | Numbers for Prometheus | 200 | — |

#### Key ideas you must be able to explain

**1. Liveness vs readiness (very likely interview question)**
- **Liveness** = "is the program alive?" If it fails, Kubernetes **restarts** the
  container.
- **Readiness** = "can it serve traffic right now?" If it fails, Kubernetes **stops
  sending requests** to it but does not restart it.
- That's why `/health/live` deliberately does **not** check the database. If the
  database goes down, restarting the API wouldn't fix anything. It would only cause a
  restart loop. The brief tests exactly this on Day 5.

**2. "Bounded" readiness check.** In `db.py`, `connect_timeout` and
`statement_timeout` make the check give up after 2 seconds instead of hanging
forever. "Bounded" means it has a time limit.

**3. Database migrations.** Instead of creating tables by hand, each schema change
is a numbered file in `migrations/versions/`. Running `alembic upgrade head` applies
any that haven't run yet. This gives you a **versioned history** of the database,
like Git for your tables. Later (Day 2) migrations run **once as a Kubernetes Job**,
not every time a replica starts. The brief requires that.

**4. Configuration from environment variables.** `config.py` reads
`DATABASE_URL`, `APP_VERSION`, etc. from the environment. The same code and image
runs in staging and production-lab; only the environment changes. No passwords in
code.

**5. Metrics.** `/metrics` exposes three things Prometheus will collect on Day 4:
- `http_requests_total`: request count, by route and status code
- `http_request_duration_seconds`: a latency **histogram** (used to calculate p95)
- `http_request_errors_total`: 5xx errors

The `route` label uses the **template** `/tickets/{ticket_id}`, not
`/tickets/57`. Otherwise every ticket ID would create a new metric series and
overload Prometheus.

**6. Structured JSON logs.** Every request writes one line like:
```json
{"timestamp": "2026-10-09T17:01:02+00:00", "level": "INFO", "message": "request",
 "release": "0.1.0", "commit": "abc1234", "request_id": "1a54...", "method": "GET",
 "route": "/health/ready", "status": 200, "duration_ms": 2.15}
```
JSON logs can be searched and filtered by tools. The brief requires that ticket text
and passwords are **never** logged. There's a test that proves this.

**7. Request ID.** Each request gets a unique ID (or reuses the `X-Request-ID`
header if the caller sent one). It's returned in the response header and written in
the log, so you can find the exact log line for a failing request.

---

## Part F: Run it (1 hour)

All commands run from inside your `supportflow-platform` folder.

### F1. Create a Python virtual environment ☐

A virtual environment keeps this project's libraries separate from the rest of your
computer.

**Windows (PowerShell):**
```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
```
> If PowerShell says scripts are disabled, run once:
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, then try again.

**Mac/Linux:**
```bash
python3 -m venv .venv
source .venv/bin/activate
```

Your prompt now starts with `(.venv)`. **Activate it again every time you open a
new terminal.**

Install the libraries:
```bash
pip install -r requirements-dev.txt
```

### F2. Create your local settings file ☐

```bash
# Mac/Linux
cp .env.example .env
# Windows
copy .env.example .env
```

`.env` is in `.gitignore`, so it's never committed.

The app reads real environment variables, not the `.env` file directly. The
defaults in `config.py` already match the local database, so **you don't need to
set anything for local use.** `.env.example` documents which settings exist.

### F3. Start PostgreSQL ☐

```bash
docker compose up -d
docker compose ps
```
Wait until the `STATUS` column shows `healthy` (about 10 seconds).

**What happened:** Docker downloaded the official PostgreSQL 16 image and started it
on port 5432. It also created a second database, `supportflow_test`, for the
automated tests (from `scripts/create-test-db.sql`).

### F4. Run the database migration ☐

```bash
alembic upgrade head
```
Expected output ends with:
```
INFO  [alembic.runtime.migration] Running upgrade  -> 0001, Create the tickets table.
```
Run it again. This time there's no "Running upgrade" line, because each migration
only runs once. That's the point.

Check the table exists:
```bash
docker exec -it supportflow-db psql -U supportflow -c "\d tickets"
```

### F5. Seed 1,000 fake tickets ☐

The brief requires at least 1,000 tickets of synthetic data.
```bash
python scripts/seed_tickets.py
```
Expected:
```
Inserted 1000 tickets. Total tickets in database: 1000
```
> Run it only once. Each run adds another 1,000.

### F6. Start the API ☐

```bash
uvicorn app.main:app --reload --port 8000
```
Leave this terminal running. You'll see JSON log lines appear as requests come in.

### F7. Try it in your browser ☐

Open **http://localhost:8000/docs**. FastAPI creates this interactive page
automatically (it's called Swagger UI). Try each endpoint:

1. `POST /tickets` → *Try it out* → body:
   ```json
   {"subject": "Printer offline", "description": "Synthetic test", "priority": "high"}
   ```
   → *Execute* → expect **201** and an `id`.
2. Try again with `"priority": "urgent"` → expect **422**.
3. `GET /tickets/{ticket_id}` with your new ID → **200**. With `999999` → **404**.
4. `PATCH /tickets/{ticket_id}` with `{"status": "in_progress"}` → **200**.
5. `GET /tickets` with `limit=5` → see `total: 1001`.
6. Open http://localhost:8000/health/ready, http://localhost:8000/version and
   http://localhost:8000/metrics.

### F8. Run the smoke test ☐

Open a **second** terminal, activate the venv again (step F1), then:
```bash
python scripts/smoke_test.py
```
Expected: ten lines starting with `[PASS]` and `ALL CHECKS PASSED`.

### F9. Prove readiness vs liveness ☐

With the API still running:
```bash
docker compose stop db
```
Open http://localhost:8000/health/ready → **503** `{"status":"not_ready",...}`
Open http://localhost:8000/health/live → still **200** `{"status":"alive"}`

```bash
docker compose start db
```
Wait about 5 seconds, then refresh `/health/ready` → **200** again. The app recovered
**without restarting**. This is a small preview of the Day 5 failure exercise.

---

## Part G: Tests and linting (30 minutes)

Stop the API (Ctrl + C in its terminal). The database must still be running.

### G1. Run the automated tests ☐

```bash
pytest
```
Expected: `19 passed`.

**What the tests check:**
- `tests/test_tickets.py`: the API contract. Correct status codes (201, 404, 422),
  pagination, maximum page size, status updates.
- `tests/test_operations.py`: health checks (including **database down → 503 while
  liveness stays 200**), version, metrics, and that logs are JSON and **don't
  contain ticket text**.

The tests use a **separate database** (`supportflow_test`) and build it by running
the real migrations, so they also prove the migrations work. They never touch your
1,000 seeded tickets.

### G2. Run the linter ☐

```bash
ruff check .
ruff format --check .
```
Expected: `All checks passed!` and `... files already formatted`.

The linter catches mistakes and keeps the code style consistent. On Day 3, GitHub
Actions runs these same commands automatically on every pull request.

---

## Part H: Commit, pull request, evidence (1 hour)

### H1. Save evidence ☐

The brief says *"screenshots alone are insufficient"*, so save real command output.

**Mac/Linux:**
```bash
mkdir -p docs/evidence
pytest 2>&1 | tee docs/evidence/day1-pytest.txt
python scripts/smoke_test.py 2>&1 | tee docs/evidence/day1-smoke-test.txt
```
**Windows (PowerShell):**
```powershell
mkdir docs\evidence -Force
pytest 2>&1 | Tee-Object docs\evidence\day1-pytest.txt
python scripts\smoke_test.py 2>&1 | Tee-Object docs\evidence\day1-smoke-test.txt
```
(Start the API again before running the smoke test.)

Then update `docs/acceptance-evidence.md` and fill in the Day 1 rows.

### H2. Check nothing secret is being committed ☐

```bash
git status
```
Make sure you **don't** see `.env` or `.venv/`. They should be ignored. If you see
them, check that `.gitignore` was copied.

### H3. Commit and push ☐

```bash
git add .
git commit -m "Add SupportFlow ticket API, migrations, tests and Day 1 docs"
git push -u origin feature/2-ticket-api
```

### H4. Open a pull request ☐

On GitHub you'll see a yellow banner → **Compare & pull request**. Write:

- **Title:** `Ticket API with health, metrics, migrations and tests`
- **Description:**
  ```
  Closes #1, #2, #3, #4

  What: FastAPI ticket service, PostgreSQL migration, 1,000-ticket seed script,
  health/version/metrics endpoints, JSON logging, 19 tests.

  Evidence: docs/evidence/day1-pytest.txt, docs/evidence/day1-smoke-test.txt

  AI assistance: starter code generated with AI help; reviewed and understood by me.
  See docs/ai-assistance.md.
  ```
Then **Merge pull request**. The `Closes #…` words close the issues automatically.

### H5. Update your local main ☐

```bash
git checkout main
git pull
```

---

## End-of-day checklist

- [ ] Email sent to SkillAnthem about timeline and scope
- [ ] AWS root MFA on, budget alert created, region chosen
- [ ] All tools installed and printing versions
- [ ] GitHub repo created, issues created, `main` protected
- [ ] `docs/decisions.md` and `docs/ai-assistance.md` read and adjusted
- [ ] API runs locally and every endpoint works in `/docs`
- [ ] 1,000 tickets seeded
- [ ] Readiness returns 503 when the database is stopped; liveness stays 200
- [ ] `pytest` shows 19 passed; `ruff` shows all checks passed
- [ ] Evidence saved in `docs/evidence/`
- [ ] Pull request merged into `main`

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `python` not found (Windows) | Reinstall Python with "Add to PATH" ticked, open a new terminal. Or try `py` instead of `python`. |
| `Activate.ps1 cannot be loaded` | Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once. |
| `docker: command not found` / cannot connect | Start Docker Desktop and wait for "Engine running". |
| `port 5432 already in use` | Another PostgreSQL is running on your laptop. Stop it, or change compose to `"5433:5432"` and set `DATABASE_URL` to use port 5433. |
| `connection refused` when running alembic/pytest | The database isn't running. Run `docker compose up -d` and wait for `healthy`. |
| `database "supportflow_test" does not exist` | The DB volume existed before the SQL script was added. Run `docker compose down -v` (**deletes local data**), then `docker compose up -d` and repeat F4–F5. |
| `ModuleNotFoundError: No module named 'fastapi'` | The venv isn't active. Activate it (F1) and run `pip install -r requirements-dev.txt`. |
| `ModuleNotFoundError: No module named 'app'` | You're not in the project's root folder. `cd` into `supportflow-platform`. |

---

## Practise explaining (the assessor will ask)

Try answering these out loud without looking:

1. What's the difference between `/health/live` and `/health/ready`, and why doesn't
   liveness check the database?
2. What does `alembic upgrade head` do? Why use migrations instead of creating
   tables by hand?
3. Why does the metrics `route` label say `/tickets/{ticket_id}` instead of the real
   ID?
4. What happens, step by step, when someone sends `POST /tickets` with
   `priority: "urgent"`?
5. Why is the database password read from an environment variable and not written
   in the code?
6. Why do the tests use a separate database?

**Tomorrow (Day 2):** package the app in a Docker image, write the Helm chart, and
run two replicas plus a migration Job in a local Kubernetes cluster (k3d).
