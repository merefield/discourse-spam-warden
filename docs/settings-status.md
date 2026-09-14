# Settings implementation status

All settings in the free plugin's `config/settings.yml` have runtime consumers.

| Setting (all prefixed `spam_warden_`) | Implemented behavior |
| --- | --- |
| `enabled` | Gates scheduling, checking and enforcement; recovery remains available |
| `mode` | Observe records, Review creates review cases, Protect also permits qualified external-evidence silencing |
| `preset` | Conservative requires strong email and IP; balanced permits strong email alone |
| `check_email`, `check_ip`, `check_username` | Select identifiers sent to the provider |
| `local_signals` | Gates local evidence and activity-triggered checks |
| `reading_limited_adjustment` | Limited reading adjustment, default -5 |
| `reading_meaningful_adjustment` | Meaningful reading adjustment, default -10 |
| `reading_sustained_adjustment` | Sustained reading adjustment, default -15 |
| `no_reading_adjustment` | Eligible no-reading adjustment, default +10 |
| `confirmed_spam_points` | Points per distinct confirmed spam post, default 85 |
| `local_points_cap` | Posting and extension cap before reading, default 100; excludes confirmed spam |
| `region` | Selects the provider endpoint |
| `recheck_hours` | Schedules the registration follow-up delay; zero prevents new follow-up scheduling |
| `retention_days` | Controls daily scan cleanup, preserving pending review evidence |
| `email_confidence`, `email_frequency` | Thresholds for strong email evidence |
| `ip_confidence`, `ip_frequency` | Thresholds for strong IP evidence |
| `max_evidence_age_days` | Limits report age for strong external evidence |

Settings changes affect subsequent checks, not stored assessments. Changing the
follow-up delay does not reschedule or cancel jobs already queued. Enabling the
plugin does not backfill existing accounts. Recheck an account to apply new weights.
Weights are saved with each assessment. Detection thresholds and the duplicate/burst
weights remain constants documented in [local signals](local-signals.md).
When no enabled identifier is available, the check is skipped and remains unscored;
local signals can still request review when their review threshold is met. The
same applies during provider outages. Neither case invents an external result or
permits automatic silencing.

The Pro extension's `spam_warden_pro_enabled` setting belongs to a development
scaffold. No Pro workflows consume it yet; enabling it adds no functionality.

## Report-count scoring (policy version 8)

Four server-only settings control the per-report weights and caps: `email_report_points`
(8), `email_points_cap` (60), `ip_report_points` (3), and `ip_points_cap` (30).
The fixed recency windows (7 and 30 days) are saved with each check. The two moderate
email thresholds still control review eligibility; strong email/IP thresholds and
presets still control protection. The eight obsolete tier-scoring settings have been
removed. See [scoring and upgrade details](external-scoring.md).

`submissions_enabled` and secret `submission_api_key` control explicitly approved
reporting independently of lookups. `ai_integration` controls optional saved AI
findings and pending-review coordination. These features retain their existing
permission and confirmation safeguards.

Coverage includes the calibration examples, date boundaries, configured caps,
independent moderation rules, confirmed-spam sampling, saved-score rendering,
admin setting updates and the real account dashboard.
