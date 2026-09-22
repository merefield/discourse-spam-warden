# Classifier integration API 1

`DiscourseSpamWarden::CLASSIFIER_API_VERSION` is independent of the account-evidence
extension API. The free plugin consumes existing classifications; it does not call
a classifier or require a paid extension.

Extensions register `spam_warden_classifier_log_models`, returning the supplied
array plus their ActiveRecord log model. Required fields: `id`, `post_id`,
`reviewable_id`, `is_spam`, `reason`, `created_at`, `error`. Use a separate table;
do not create synthetic Discourse AI logs. Index post ID and review ID. Register
negative bot IDs using `spam_warden_classifier_bot_ids` for review reconciliation.
These modifiers should remain active when automatic inference is disabled so
history and staff decisions remain visible.

The same admin-only snapshot, public-topic scope, 30-day/100-post sample, ten-result
limit, human decision checks and pending-review reconciliation apply to every
provider. Queries bound each provider independently before merging results. Automated
classifications do not add risk points or authorize external submissions.

Retain the provider adapter while its historical logs are needed. Removing an
extension hides its additional findings but leaves core review records intact.
