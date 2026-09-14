# Report-count scoring (policy version 8)

The displayed percentage is a rule-based concern score, not a probability of spam.
Action eligibility is assessed separately: changing display weights cannot authorize
an automatic silence or remove an evidence-based requirement for review.

## Calculation and defaults

| Contribution | Default | Setting |
| --- | --- | --- |
| Email report | 8 points | `spam_warden_email_report_points` |
| Email cap, before recency | 60 points | `spam_warden_email_points_cap` |
| Registration IP report | 3 points | `spam_warden_ip_report_points` |
| IP cap, before recency | 30 points | `spam_warden_ip_points_cap` |
| Staff-confirmed spam | 85 per distinct post | `spam_warden_confirmed_spam_points` |

All five settings accept 0–100. The existing reading settings remain configurable.

For each identifier: `min(report count × weight, identifier cap) × recency multiplier`.
The two contributions are always added. Username matches, provider blacklist results
and AI classifications add no points. Provider reputation values remain visible and
still participate in the separate moderation rules; they are not counted again in
numeric scoring.

Recency is a fixed, simple rule applied **after** each identifier cap:

- Last reported within 7 days: full weight (×1).
- More than 7 and up to 30 days: half weight (×0.5).
- Older, missing, invalid or future report date: zero points.

Counts are cumulative and need not represent independent reports. The date is the
last report date, not the age of every report. The multiplier is a heuristic applied
to that cumulative count. Half-point results are retained, not rounded to integers.
The recency windows are recorded with each assessment.

```
external = email points + IP points
local suspicion = min(posting points + extension points, configured local cap)
suspicion = max(0, external + local suspicion + reading adjustment)
final score = min(100, suspicion + confirmed spam points)
```

Duplicates and posting bursts retain their shared 25-point cap. Extension points
retain their own 25-point cap. `spam_warden_local_points_cap` now caps posting and
extension contributions together before reading; it no longer caps or discounts
confirmed spam. Confirmed posts are added after the zero floor, so reassuring
reading cannot cancel a confirmed incident. Failed/skipped provider checks remain
unscored; local evidence can still require review without inventing an external score.

## Calibration examples

These illustrate the defaults, not measured detection accuracy.

| Account | Email | IP | Reading | Confirmed | Final |
| --- | --- | --- | --- | --- | --- |
| JeffersonAlu92 | 3 × 8 = 24 | 5 × 3 = 15 | +10 | 0 | 49 |
| MelAtkinson533 | min(9 × 8, 60) = 60 | 2 × 3 × 0.5 = 3 (last report 20 days ago) | +10 | 0 | 73 |
| MarilynnSorens | 7 × 8 = 56 | min(32 × 3, 30) = 30 | +10 | 0 | 96 |
| TylerBeck | 0 | 0 | −15, suspicion floored at 0 | 85 | 85 |

Two confirmed posts contribute 170 before the final cap, producing 100 even with
reading reassurance. With custom per-post weights, enough history is sampled to
reach 100: `max(3, ceil(100 / per-post points))`; zero weight samples three for the
independent review requirement.

## Upgrade and saved assessments

Version 8 replaces the six weak/moderate/strong/combined point settings with four
per-report/cap settings. The two moderate-IP thresholds, which only selected scoring
tiers, are removed too. Old overrides are not translated because the formulas are
not equivalent. Review/protection settings and their values remain unchanged.
Existing database setting rows need no migration and are no longer exposed or read;
saved policy JSON retains the historical settings used for each scan.

Saved assessments are never rescored on display. Version 8 stores identifier counts,
weights, caps, recency factors and calculation subtotals. The dashboard summary and
calculation use that snapshot, not current site settings or the current date. Older
assessments show a labelled legacy breakdown and their original score. Recheck an
account to apply the new defaults. No migration, automatic sweep or retroactive
moderation action is introduced.

## Dashboard

A full-width score and succinct explanation sit above a calculation column and
separate evidence cards. On narrow screens the calculation and evidence stack.
Actions follow the evidence. Detailed methodology is expandable. AI findings remain
informational; exemptions preserve their labelled blue treatment, and unknown scores
remain N/A. The user-list score uses the same saved assessment and colour bands.
