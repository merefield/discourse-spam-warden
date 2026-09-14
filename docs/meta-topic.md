| | | |
| - | - | - |
| :information_source: | **Summary** | A Discourse plugin that combines Stop Forum Spam reputation with local activity to give staff explainable account assessments, review workflows and optional automatic protection. |
| :hammer_and_wrench: | **Repository Link** | <https://github.com/merefield/discourse-spam-guard> |
| :open_book: | **Install Guide** | [How to install plugins in Discourse](https://meta.discourse.org/t/install-plugins-in-discourse/19157) |
| :heart: | **Sponsorship** | Please consider becoming an ongoing [sponsor of my open source work](https://github.com/sponsors/merefield) at a level that suits your or your organisation's resources and needs to help maintain this plugin. |

Enjoying this plugin? Please :star: it on [GitHub](https://github.com/merefield/discourse-spam-guard)! :pray:

### Why use it?

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

### Features

Discourse Spam Guard helps staff decide which accounts need attention, explains the evidence, and works with Discourse's existing review queue and moderation controls.

* Checks new registrations in the background, with an optional delayed recheck and manual checks for individual accounts.
* Looks up email and public registration IP reputation on Stop Forum Spam, with optional username evidence.
* Provides an expandable dashboard on each admin user page, with a succinct saved-score explanation, a separate calculation column and evidence cards for reputation, reading, posting and moderation history. The score and breakdown boxes align at wide container sizes, and the layout stacks on smaller screens. Account actions sit directly below the Spam Guard header; methodology is expandable.
* Adds a compact **Spam Guard** score to the admin user list. Click it to open that account's dashboard. Unchecked accounts show grey **N/A**; exempt accounts have a blue, explicitly labelled override.
* Uses configurable, explainable scoring. Email reports contribute 8 points each (cap 60), and IP reports 3 each (cap 30), with full weight when last reported within 7 days, half within 30 days, and zero for older or undated evidence. Reading adjusts suspicion once; confirmed spam adds 85 points per post separately, with a final cap of 100. These defaults are configurable except for the fixed recency windows.
* Offers **Observe**, **Review** and **Protect** modes, plus persistent account exemptions.
* Lets admins contribute independently confirmed spam back to Stop Forum Spam, with an exact-data confirmation dialog, explicit agreement, duplicate protection, delivery status and audit history. This is included in the free plugin.

The percentage is a **rule-based score, not a probability of spam**. A match is evidence for consideration, not proof. No reading activity alone does not establish spam, and a zero score does not guarantee an account is safe.

### Modes

| Mode | Behaviour |
| - | - |
| **Observe** | Records checks and evidence without placing accounts in review or silencing them. This is the default. |
| **Review** | Adds qualifying accounts to Discourse's staff review queue without automatically silencing them. |
| **Protect** | Automatically silences eligible accounts only when strict external-reputation rules are met; other qualifying accounts go to review. |

Local activity signals alone never authorize automatic silencing. Neither do IP-only or username-only matches. Manual checks never automatically silence an account, and changing scoring weights does not relax the protection rules.

Checks are asynchronous, so they cannot guarantee preventing a first spam post. Keep Discourse's existing anti-spam controls enabled. Provider outages do not authorize restrictions.

### Settings and getting started

Install the plugin using the guide above, then open **Admin → Plugins → Spam Guard**.

* Enable `spam_guard_enabled` to start reputation checks. It defaults off; start with `spam_guard_mode` set to `observe` and review the results before enabling enforcement.
* Choose `spam_guard_preset`: **conservative** requires strong recent email and IP evidence for automatic protection; **balanced** permits strong recent email evidence alone.
* Choose which identifiers to look up with `spam_guard_check_email`, `spam_guard_check_ip` and `spam_guard_check_username`. Email and IP default on; username defaults off.
* Set `spam_guard_recheck_hours` for the delayed registration recheck. It defaults to 24 hours; zero disables it.
* Adjust reputation thresholds, point weights, reading adjustments, local signals and scan retention in the plugin settings. [Scoring documentation](https://github.com/merefield/discourse-spam-guard/blob/main/docs/external-scoring.md) explains the calculation.

**No API key is required for reputation lookups.** Reporting spam back to Stop Forum Spam uses a separate API key and enable setting.

Saved assessments retain their original scores and settings. Older records show a legacy breakdown; recheck an account to apply the new formula. Report counts are cumulative, and the latest report date does not date every report.

### Discourse AI integration

Included free: saved AI classifications, explanations, scan times, post/review links
and separate human review outcomes on the admin account dashboard. Spam Guard reuses
pending AI reviews and consolidates duplicate account reviews in a background job.
`spam_guard_ai_integration` defaults on when Discourse AI is installed; AI is optional.

AI classifications add no risk points and cannot authorize reports. Human-confirmed
AI flags use the existing confirmed-spam rule and can lead to the existing account
reporting preview, with explicit admin approval. Refresh reads saved results without
additional model calls. See [integration details and scope](https://github.com/merefield/discourse-spam-guard/blob/main/docs/ai-integration.md).

### Contributing confirmed spam

Get a key from [Stop Forum Spam’s API key registration page](https://www.stopforumspam.com/signup), then enable `spam_guard_submissions_enabled` and set the secret `spam_guard_submission_api_key`. Reporting is independent of the lookup enable switch and is available to human admins only.

On an account's dashboard, choose **Preview report**. The confirmation dialog shows the destination, exact username, email, registration IP and evidence, including the post URL and excerpt. It discloses API-key authentication without exposing the secret. An agreement checkbox is required before submitting; Cancel sends nothing.

A qualifying report requires a spam flag agreed with by human staff within the last 30 days on a retained post from a public topic. Staff and exempt accounts, unconfirmed registrations, private messages and restricted categories are excluded. A high score or existing Stop Forum Spam match alone cannot qualify an account for reporting.

After approval, the dashboard shows **Queued**. Use **Refresh submission status** to check delivery. **Submitted successfully** means the provider returned JSON success or its documented empty HTTP 200 success response. History shows the approving admin’s current username linked to their admin page, with an ID fallback for deleted accounts. Uncertain deliveries are blocked from resubmission to avoid duplicates; the dashboard explains recovery options. Existing uncertain records are not automatically reclassified after upgrading.

Reporting is always a separate, explicit action: choosing Review or Protect mode does not send reports. See [reporting safeguards and recovery](https://github.com/merefield/discourse-spam-guard/blob/main/docs/submissions.md).

### Privacy and storage

Admin dashboards, user-list summaries, settings and reporting endpoints are admin-only. Moderators can see review evidence and use moderation actions within their normal Discourse permissions. Persistent exemptions are admin-only.

Reputation lookups transmit the enabled identifiers to Stop Forum Spam. Reporting transmits the exact identifiers and evidence approved in the confirmation dialog, which the provider may publish. Local scan records store normalized evidence; submission records retain internal IDs, a payload hash and delivery history rather than raw identifiers or post content.

Account deletion and anonymization remove the plugin's local records. Removing local data, granting an exemption or disabling reporting does not retract an external report; corrections must be handled with Stop Forum Spam.

### Pro extension

The features described above are included in the free, GPLv2 plugin. An optional Pro extension is planned for advanced analysis and larger moderation workflows; its additional features are not available yet. Individual confirmed-spam reporting and its safeguards remain free.

**[Support ongoing development on GitHub](https://github.com/sponsors/merefield)**
