# Local signals (policy version 8)

The free plugin includes exact duplicate posts, posting bursts and confirmed spam
moderation history. These are deterministic rules; no keywords, semantic analysis,
domain analysis or LLM calls are involved. The `spam_warden_local_signals` setting
enables them by default when Spam Warden itself is enabled. Observe mode remains
the default for the plugin and is recommended while evaluating the rules.

| Signal | Evidence window and threshold | Contribution |
| --- | --- | --- |
| Exact duplicates | Identical raw text of at least 40 characters in at least three distinct public topics within 24 hours | +20 |
| Posting burst | At least five posts across at least three public topics within ten minutes | +15 |
| Confirmed spam | Distinct posts with spam flags agreed with by human staff in the last 30 days | +85 per post by default, configurable |

Duplicate and burst contributions share a 25-point cap. Posting and extension points
share the configurable local cap before reading. Add external points and reading,
then floor suspicion at zero. Confirmed spam points are added separately afterwards;
reading never discounts them. The final score is capped at 100. One posting signal
produces watch; combined posting evidence or confirmed spam history can request
review in Review or Protect mode. Observe mode only records evidence.

Confirmed spam requires review even when admins configure its points or the local
cap to zero. With no external match, one confirmed post and sustained reading gives
`max(0, -15) + 85 = 85`; two give `max(0, -15) + 170`, capped to 100. There is no special
repeat-offence weight or decision floor in that arithmetic.
Local points never authorize a silence, including when they raise the displayed
score into the red band after reading reduced an external silence recommendation to review.
Unavailable or skipped provider checks remain unscored. Local evidence can still
request review at its normal threshold, but cannot authorize automatic silencing.

Posting examines at most the latest 100 undeleted regular posts from the last
24 hours, in undeleted public regular topics. Personal messages, restricted
categories, system posts and other authors are excluded. Exact comparison hashes
are computed in SQL; raw post text and hashes are not retained in scan evidence.
Only counts and contributions are stored, alongside the existing reading snapshot.

History uses agreed spam scores on approved `ReviewableFlaggedPost` records, with
a positive-ID reviewer who is currently an admin or moderator. Multiple flags on
one post count once. Pending, disagreed, ignored, non-spam and automated decisions
are excluded, as are Spam Warden's own reviewables. The history sample is bounded by `max(3, ceil(100 / per-post points))`; a zero
weight samples three. Two confirmed posts at the default weight reach the final cap. Reversed
agreements stop contributing at the next check. Deletion or silence without a
confirmed spam flag is not evidence. No new history table or migration is needed.

Public post creation and flagged-post review transitions schedule a check one
minute later. A per-account queue reservation coalesces repeated events before
enqueueing. Activity during a check can schedule a follow-up. Activity checks
preserve the existing staff, age (seven days),
trust-level (above one) and account-exemption exclusions. Within the per-user lock,
checks within one minute of the last activity scan reuse it, preventing repeated
lookups and records during a burst; a deferred follow-up preserves activity that
arrived during that cooldown. Provider caching and global limits still apply.
Manual checks can assess older ordinary accounts. Existing registration and
delayed checks also include local signals. Turning off local signals stops queued
activity checks and excludes their contribution from subsequent assessments.

There is no periodic sweep or post-edit hook. Scores are snapshots and do not
change as evidence ages until another check occurs. None of these asynchronous
checks guarantees blocking the first post. Existing Discourse posting limits and
moderation continue to apply.

Never posting and having an unconfirmed email add no local risk points. If shown
in a future account-context section, these states should use neutral text rather
than warning colours or scored-evidence cards. The existing zero-reading adjustment
is separate and unchanged; inactivity is not counted again here.

Repeated destination-domain detection, links added through edits, trusted-domain
exceptions, complex keyword rules, semantic analysis and LLM analysis remain Pro
features and are not implemented by these checks.
