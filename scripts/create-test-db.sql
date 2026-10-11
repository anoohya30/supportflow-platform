-- Runs once when the local Postgres container is first created.
-- A separate database for automated tests, so tests never wipe your dev data.
CREATE DATABASE supportflow_test OWNER supportflow;
