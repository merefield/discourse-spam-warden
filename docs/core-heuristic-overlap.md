# Heuristics and core prevention

Checked against the local Discourse implementation on 2026-09-05. Values below
are core defaults, not a claim about every deployed site's configuration.

| Signal | Core control | Remaining purpose |
| --- | --- | --- |
| Exact duplicate posts across topics | `unique_posts_mins` defaults to 5; `PostValidator` rejects the same author's identical raw text while its Redis key exists | Spam Warden examines up to 100 public posts over 24 hours, catching spaced repeats after the core window expires |
| Five posts across three topics in ten minutes | Posting intervals default to 30 seconds for new users and 5 seconds otherwise; first-day quotas also apply | Five replies spread across topics can fit within those limits; the signal measures a pattern, not a rate-limit violation |
| Staff-confirmed spam history | Core can hide posts, silence or delete accounts, depending on the moderation action and configured flag rules | Agreeing with spam does not universally mean a permanent account restriction; retained history remains useful for subsequent checks and explanations |
| Reading activity | Core uses activity for trust progression and can impose group/trust posting controls | Posting need not require reading first; reading can supply context but is not proof of legitimacy |
| Stop Forum Spam evidence | Core has local screened-address controls and other spam checks | Local blocking is not the same evidence source as external reputation; never override a core block |

## Duplicate control details

`Post#unique_post_key` includes the author ID and a hash of raw text, but not the
public topic ID. Moving the same text into another public topic therefore does
not bypass the five-minute guard. PMs use a separate namespace and are excluded
from Spam Warden's public-post sampling.

At default settings, an identical message posted at minutes 0, 6 and 12 can pass
core's uniqueness window and still meet Spam Warden's three-topic rule. Staff and
explicit skip-validation/import paths have different behavior, but normal users
waiting beyond the window are enough to justify the heuristic. Spam Warden itself
excludes staff accounts. Setting the core window to zero disables its duplicate
guard; making it cover the entire plugin lookback reduces the plugin signal's
incremental value substantially.

The plugin counts successfully stored posts, not rejected posting attempts. It
does not currently detect tiny textual changes or attempted duplicate submissions.
Existing fixture-based examples are supplemented by a `PostCreator` regression
that verifies immediate rejection and later permitted duplication after expiry.

## Practical decisions

Keep the existing free signals: none is universally impossible under core defaults.
Treat duplicate detection as longer-window repetition and posting bursts as
corroborating evidence. Both remain subject to the existing posting-point cap and
never authorize automatic silencing. Restrictive site configuration can reduce
their usefulness; it does not justify bypassing core controls.

For future Pro keyword/link analysis, inspect core watched words and linked-host
spam controls before building equivalent prevention. Prefer adding investigation
and explanations around core decisions where the underlying rule already exists.

Implementation anchors: `lib/validators/post_validator.rb`, `app/models/post.rb`,
`lib/post_creator.rb`, `app/models/reviewable_flagged_post.rb`,
`lib/new_post_manager.rb`, and `config/site_settings.yml` in core.
