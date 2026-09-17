# Query performance

Updated on 2026-09-05 after query, queue and locking improvements.

## Query shape

An enabled local assessment issues three measurement SELECTs: one UserStat lookup,
one recent-post query and one confirmed-spam history query. Reading uses existing
counters, selecting only the five required fields.

The post query uses the existing author/date index. A subquery limits eligible
public posts to 100 before the outer projection computes content hashes. Only
topic IDs, timestamps and hashes reach Ruby. The populated query plan confirms
that hashing occurs above the limit.

History uses EXISTS for matching scores and normally stops after three qualifying
reviewables. Lower configured per-post weights increase the bound to enough posts
to reach the final score cap without any discount from reading:
`max(3, ceil(100 / points_per_post))`. A zero weight uses
three rows for review evidence; positive weights require at most 100 rows under
the setting bounds. Discourse's unique (type, target_id) index guarantees each flagged
post is counted once. No DISTINCT, duplicate flag expansion or deduplication sort
is needed. The populated plan uses existing author and score-reviewable indexes.

Admin lists add two batch queries, independent of user count. The latest-result
query uses a lateral indexed lookup per listed account inside one SQL statement.
It reads one result per account, rather than scanning all retained history.
Composite indexes support user/date/ID and user/source/date/ID ordering. List,
single-account and source-specific lookups use created_at DESC, id DESC consistently.

## Queue and locking

A per-account Redis reservation combines activity events before enqueueing.
Reservation and submission run after database commit. Rollbacks leave no queued
job or reservation; failed queue pushes release their own reservation. Reservations
expire after six hours for recovery from abandoned jobs.

Workers release their own token before checking so activity during processing can
enqueue a follow-up. Token comparison prevents old workers from releasing newer
reservations. If the execution cooldown reuses an earlier scan, a coalesced
follow-up is scheduled so intervening activity is not lost. Outage retries use
the same queue and remain bounded to two retries.

Provider access and all three measurements run outside the user row lock. The
per-user distributed mutex still serializes checks. The locked section reloads
the user and rechecks eligibility, exemptions, settings and identifiers before
persisting or acting. Disabling local signals before the locked decision removes
their contribution. Measurements remain snapshots; concurrent activity is
collected by the following check.

## Populated-data verification

Run `bin/rspec plugins/discourse-spam-warden/docs/query-profile.rb` with plugins
loaded. The standalone profile creates 100,000 scans across ten accounts, 10,000
posts and 100,000 flag scores inside a rolled-back test transaction. It prints
plans; timings are not pass/fail assertions.

| Query | Local execution time | Observed work |
| --- | --- | --- |
| Previous latest-list query | 13.032 ms | Read all 100,000 scans |
| New latest-list query | 0.057 ms | One indexed row per account, ten rows total |
| Recent-post sample | 0.803 ms | 100 content hashes after LIMIT |
| Previous positive-history query | 0.048 ms | Expanded duplicate flags before uniqueness |
| New positive-history query | 0.027 ms | Three reviewables, first qualifying score each |
| New history with all 10,000 account flags expired | 4.197 ms | Proved absence of current qualifying scores |

These are warm-cache synthetic measurements, not production latency guarantees.
Filtering still examines candidates when few or no records qualify; proving
absence is not constant-time. No speculative indexes were added to core tables.
