# Decision: Load-test toolkit location

- **Date:** 2026-10-09
- **Status:** Accepted — implemented in `e8773ac` (branch `chore/move-loadtests`)
- **Applies to:** backend performance tooling

## Context

The load-test toolkit (Node runner, k6 script, results analyzer, compose
stack, Prometheus config, guide) was authored directly into the Flutter
repo root. The root is the app module — `pubspec.yaml`, `lib/`, `test/`
and the Android/iOS scaffolding all live there.

## Decision

Move the toolkit to **`backend/server/loadtest/`**.

## Rationale

It is backend performance tooling with no Flutter dependency: it drives the
Express API over HTTP and measures server latency. Keeping it out of the app
module keeps the app's dependency surface honest — nothing in
`pubspec.yaml` should imply a load generator ships to users, and `flutter
build` should not have anything to reason about.

It also sits next to what it measures (`backend/server/src/`) rather than
being separated from it by the entire Flutter app.

## Consequences

Path repairs were required as part of the move, because the files had been
written assuming the repo root:

- compose build context `./backend/server` → `..`
- the `migrations/` initdb mount was **removed** — no such directory
  exists; schema is owned by `backend/server/src/db.ts`
  (10 × `CREATE TABLE IF NOT EXISTS` on boot). Mounting a missing path is a
  hard compose failure, and mounting an empty one would hide the fact that
  the database starts empty.
- `grafana/datasources/prometheus.yml` and `grafana/dashboards/` were added
  because a missing bind-mount source also fails startup. The datasource is
  the one the guide already promised.
- `LOAD_TESTING_GUIDE.md` gained a **Location** section pinning every
  command to the new directory.

Dashboards themselves are deferred to Part F8.