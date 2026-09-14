# Discourse Spam Guard

Explainable Stop Forum Spam reputation checks, account risk dashboards and moderation
workflows for Discourse. The free plugin also supports individually approved reports
of locally confirmed spam back to Stop Forum Spam. Licensed under GPLv2.

## Why use it?

Spam Guard brings external reputation and activity on your own forum together in
one place, so staff can see why an account needs attention and decide what to do.

- **Understand the evidence.** Inspect the reports, their recency, reading activity
  and confirmed spam history behind a score instead of acting on an unexplained label.
- **Choose how much to automate.** Start by observing, move qualifying accounts into
  the existing staff review queue, or enable automatic silencing under stricter rules.
- **Keep moderation in Discourse.** Open an account assessment directly from the admin
  user list, review the evidence and manage exemptions alongside familiar staff tools.
- **Use existing AI findings.** See AI classifications alongside human review outcomes,
  coordinate pending reviews and report human-confirmed spam without extra model calls.
- **Contribute useful data back.** Report independently confirmed spam to Stop Forum
  Spam after reviewing exactly what will be shared. Individual reporting and its
  safeguards are included free.

It complements Discourse's existing anti-spam controls. The aim is to help staff
prioritize accounts and make informed decisions, while keeping the difference
between suspicion, confirmed spam and an action taken explicit.

## Features

- Background registration checks, an optional delayed recheck and manual account checks.
- Email and public registration IP reputation, with optional username evidence.
- An expandable admin user dashboard showing evidence, score breakdown, activity,
  moderation history and action taken.
- A compact Spam Guard column on the admin user list, linking directly to the expanded
  dashboard. Missing assessments show grey N/A; exemptions show a labelled blue override.
- Configurable per-report weights and caps, one reading adjustment, and capped
  local signals from duplicate posts, posting bursts and staff-confirmed spam posts.
- Observe, Review and Protect modes using Discourse's existing review and moderation tools.
- Admin-approved spam reporting with an exact-data confirmation dialog, duplicate
  protection, conservative delivery recovery and submission history.

Scores are rule-based indicators, not probabilities. Zero does not guarantee safety;
reputation matches and lack of reading are signals, not proof of spam.

## Installation and setup

Follow [Discourse's plugin installation guide](https://meta.discourse.org/t/install-plugins-in-discourse/19157)
using `https://github.com/merefield/discourse-spam-guard.git`. Installation or upgrade
requires the plugin migrations and a restart/rebuild of the application and background workers.

Open **Admin → Plugins → Spam Guard**. Enable `spam_guard_enabled` and start with
`spam_guard_mode` set to `observe`. Checks default off. **Reputation lookups need no API key.**
Email and IP lookups default on; username lookup defaults off. The delayed recheck
is 24 hours by default; set `spam_guard_recheck_hours` to zero to disable it.

| Mode | Behaviour |
| --- | --- |
| Observe | Records evidence without queuing reviews or imposing restrictions. |
| Review | Adds qualifying accounts to the staff review queue without automatic silencing. |
| Protect | Automatically silences only when strict external-reputation rules permit it; other qualifying accounts go to review. |

The conservative preset requires strong, recent email and IP evidence for automatic
silencing; balanced permits strong, recent email evidence alone. IP-only, username-only
and local signals never authorize automatic silencing. Manual checks never automatically
silence. Scores do not replace these eligibility rules.

Checks run asynchronously and cannot guarantee stopping a first post. Existing Discourse
rate limits and moderation controls still apply. Provider outages never authorize a
restriction. Automatic checks exclude staff, accounts older than seven days, trust
levels above one and explicit exemptions; manual checks can examine older ordinary accounts.

## Scoring

Email reports contribute 8 points each (cap 60); registration IP reports contribute
3 points each (cap 30). Each identifier receives full weight if last reported within
7 days, half within 30 days, and zero beyond 30 days or without a valid date. Counts
are cumulative; the latest report date does not date every report.

Reading adjusts external and posting suspicion once, with a minimum of zero.
Staff-confirmed spam then adds 85 points per post, unaffected by reassuring reading.
The final score is capped at 100. Weights and caps are configurable; action rules
remain separate. Username and AI evidence add no numeric points.

The account dashboard places a succinct saved-score explanation above a compact
calculation column and separate evidence cards. It stacks on smaller screens, with
methodology expandable and account actions directly below the Spam Guard header.
At wide container sizes, the risk score and breakdown boxes align in one column.
Saved assessments keep their original
scores and weights; older records show a legacy breakdown. Recheck to apply version 8.

See [external scoring and upgrade details](docs/external-scoring.md),
[reading activity](docs/engagement-assessment.md), [local signals](docs/local-signals.md)
and [status design](docs/status-design.md).

## Discourse AI integration

The free plugin optionally shows saved AI spam findings, human review outcomes and
post/review links on the account dashboard. It reuses pending AI reviews and consolidates
duplicate account reviews. `spam_guard_ai_integration` defaults on when AI is installed.
AI classifications add no risk points; human-confirmed spam uses the existing rule.
Confirmed findings link to the existing, explicitly approved account reporting preview.
No additional LLM calls are made. See [AI integration](docs/ai-integration.md).

## Reporting confirmed spam

Reporting has separate controls: enable `spam_guard_submissions_enabled` and configure
the secret `spam_guard_submission_api_key`, available from
[Stop Forum Spam’s API key registration page](https://www.stopforumspam.com/signup).
Reporting, retained evidence and recovery
remain accessible when lookups are disabled.

Open a user's Spam Guard dashboard and choose **Preview report**. The confirmation
dialog shows the destination, exact identifiers and evidence. The admin must explicitly
agree before submitting. Eligibility requires independently staff-confirmed spam in a
public topic; suspicious registrations and high scores alone do not qualify.

After approval, the dashboard shows **Queued**. Click **Refresh submission status** to
retrieve the result without reloading the page. The plugin recognises both JSON success
and the provider’s documented empty HTTP 200 success response. Submission history
shows the approving admin’s current username linked to their admin page, with an ID
fallback for deleted accounts. Uncertain deliveries are never blindly retried; existing
uncertain records are not automatically reclassified after upgrading. Review and Protect
modes do not automatically submit reports.

See [reporting setup, safeguards, retention and recovery](docs/submissions.md).

## Permissions and privacy

Admin dashboards, user-list summaries, settings, reporting and persistent exemptions
are admin-only. Moderators can view review evidence and take actions permitted by
Discourse's normal moderation permissions.

Enabled reputation lookups send the selected identifiers to Stop Forum Spam. Reporting
sends the approved identifiers and evidence, which the provider may publish. The API key
stays server-side. Scan records store normalized evidence; lookup cache keys hash inputs.
Submission records store internal IDs, a payload hash, status and history without raw
email, IP, post content or credentials.

Account deletion and anonymization remove plugin records. Submission records otherwise
remain independently of scan retention to prevent duplicate reports. Local removal or an
exemption does not retract a report already sent to Stop Forum Spam.

**Allow this account** grants an exemption and only reverses a silence still owned by
Spam Guard. Independent staff silences and suspensions are preserved. Removing an
exemption does not immediately reenforce an old decision.

## Core integration and development

The plugin runs against upstream Discourse without core patches. It uses the plugin API,
admin outlets, core reviewables and reloadable extensions to batch-load saved evidence.
Browsing the user list does not call Stop Forum Spam. See the [integration audit](docs/core-integration-audit.md).

GitHub Actions uses Discourse's standard reusable plugin workflow against upstream
`latest`, covering lint, backend, frontend, system and model annotations.

```sh
LOAD_PLUGINS=1 bin/rspec plugins/discourse-spam-guard/spec
bin/qunit --standalone --target discourse-spam-guard
```

Run these from a Discourse checkout with the plugin installed. Provider requests in tests
are mocked; tests do not submit real reports. The development repositories can be symlinked
from `~/code` into `~/discourse/plugins`. Unrelated installed plugins may require an isolated
test checkout to avoid dependency conflicts.

## Sponsorship and Pro

All features above are free. The Pro extension currently establishes a dependency boundary;
its advanced workflows are not implemented yet. Individual reporting and its safeguards
remain part of the free plugin.

[Support ongoing development](https://github.com/sponsors/merefield).
The [Meta introduction](docs/meta-topic.md) is a ready-to-paste plugin topic draft.
