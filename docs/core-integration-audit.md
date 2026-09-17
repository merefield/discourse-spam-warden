# Discourse integration audit

## Upstream compatibility correction

Upstream CI exposed that the proposed preload events and column transformer were
local core changes, not upstream APIs. They are no longer deployment requirements.

- A reloadable extension of `Admin::UsersController#serialize_data` prepares only
  `AdminUserListSerializer` collections, retaining the admin guardian check and
  two batched evidence queries after core has filtered and paginated users.
- A reloadable extension of `Reviewable.list_for` extends the returned relation's
  `records` method. Evidence loads after core associations, only for the loaded
  page. Count queries stay lazy; repeated reads reuse the loaded evidence.
- The admin-only frontend initializer extends `columnCount` through
  `api.modifyClass`, adding one to core's result so optional core columns still
  work. It does not register an unavailable transformer.

These narrow extensions call `super` and preserve core filtering, permissions and
pagination. They are compatibility surfaces covered by request/query and browser
regression tests against unmodified upstream Discourse. Dedicated upstream hooks
would let us retire them in future. The earlier audit below records the proposed
hook-based approach, which this correction supersedes.

Reviewed against the local Discourse checkout on 2026-09-05. The findings below
record the original audit. Runtime fixes have subsequently been implemented.

## Resolution

- Lifecycle listeners now run independently of checking enablement. Disabled-state
  anonymisation and deletion have regression coverage.
- A generic core `reviewables_preloaded` event allows one batch scan query; nested
  evidence reuses the target already loaded by core. Single-review requests retain
  a lazy fallback. Server-side review action translations were also corrected.
- Dashboard/review links use `getURL`, including the dashboard-opening query.
- Staff silence reasons identify a staff review decision. Automatic actions retain
  the external-evidence reason. Failed silence operations leave reviews pending;
  existing restrictions have a distinct confirmation action.
- Exception updates resolve a pending review through one action and log once.
- Core `admin_user_list_preloaded` replaces the query-method prepend. The
  `admin-user-list-column-count` transformer replaces the column-count override.
  The small account query-parameter registration remains covered by real router
  acceptance tests. It does not override core controller behavior.
- The manual form uses the core user chooser and submits the selected account ID.
- Qualifying local evidence can request review when a provider check fails or is
  skipped. Such assessments remain unscored and cannot automatically silence.
- `spam_warden_additional_evidence` is a core registry modifier called before
  assessment, outside the user row lock. Contributions are bounded, displayed and
  persisted. Extension failures leave free checks working; contributions can
  request review but never elevate a decision to automatic silence.

The earlier proposal required three accompanying core changes; this is superseded above. They are generic
extension points but are not assumed to be present in upstream Discourse.
See the README and the extension contract for details.

## Original assessment

The free plugin uses the right core foundations. It does not need an architectural
rewrite. Lifecycle handling, review serialization and a few UI/moderation details
need correction before describing the integration as complete.

| Area | Existing core integration | Assessment |
| --- | --- | --- |
| Moderation | `UserSilencer`, Guardian, `UserHistory`, `StaffActionLogger` | Correct foundations; preserve this boundary |
| Review workflow | Registered `Reviewable` subclass, scores, actions, histories and core queue | Correct architecture; loading and action-result gaps below |
| Reading activity | Existing `UserStat` counters | No duplicate tracking system |
| Posting evidence | Core posts, topics and category visibility | Bounded public-post sampling; private messages excluded |
| Confirmed spam | Agreed spam `ReviewableScore` records on approved flagged-post reviews | Uses recorded staff decisions rather than treating raw flags as proof |
| Automation | Core events, `Jobs`, scheduled cleanup, `DB.after_commit` | Appropriate; Redis reservations add coalescing rather than a second scheduler |
| Concurrency and throttling | `DistributedMutex`, row locks, `Discourse.redis`, `RateLimiter` | Appropriate reuse; provider-specific circuit/cache remain plugin responsibilities |
| Settings and permissions | Site settings, admin controller, `Service::Base` contracts/policies | Uses core infrastructure; admin management and staff review permissions intentionally differ |
| Admin UI | Modern plugin route, plugin navigation, outlets, serializer extension, FormKit, standard buttons/table classes | Mostly native; internal patches and links need attention |
| Evidence storage | Plugin scan/account tables linked to core users and reviewables | Appropriate for historical evidence and exception ownership; avoid duplicating core sanctions |
| Pro | Version check and shared post-check event | Scaffold only; no implemented Pro features to audit |

## Original findings in priority order

### High: anonymisation cleanup stops when the plugin is disabled

`plugin.rb:69–77` registers deletion/anonymisation using the plugin `on` helper.
Core `lib/plugin/instance.rb:673` gates that helper on `enabled?`. Consequently,
anonymising an account while `spam_warden_enabled` is false leaves its scans and
exception record attached to the anonymised user. Daily orphan cleanup cannot
repair this because the user still exists. Pending review evidence is also exempt
from normal age-based scan expiry. Deletion leaves records until orphan cleanup.

Use lifecycle listeners that run independently of feature enablement, following
core reload conventions. Keep checks/enforcement gated. Add disabled-state
anonymisation and deletion coverage; current lifecycle coverage enables the plugin.

### Medium: review serialization has N+1 queries

`app/serializers/reviewable_spam_warden_serializer.rb:7` finds the referenced scan
for every review. `SpamWardenScanSerializer#username` then loads `scan.user`.
Core `Reviewable.viewable_by` preloads the review target, but neither the scan nor
that separately loaded scan's user association. A page with N matching reviews
therefore adds approximately 2N queries when their scans exist.

Batch-load scans at the review collection boundary and reuse the preloaded target
for the username. Verify both list and single-review serialization with query
counts. The existing batched admin user list does not suffer from this issue.

### Medium: some links bypass core subfolder routing

`spam-warden-dashboard.gjs` and `reviewable-spam-warden.gjs` construct root-relative
`/admin/users/...` and `/review/...` hrefs. These omit the installation prefix on
subfolder deployments. The compact user-list summary already uses `getURL`.

Use core `LinkTo` routing or `getURL` consistently. Where appropriate, reuse the
existing dashboard-opening query parameter. Verify navigation with a subfolder
configuration as well as the normal root installation.

### Medium: manual silence records the wrong evidence source

`Moderation.silence` always uses the translation stating that strong Stop Forum
Spam reputation evidence caused the action. A review can instead arise from local
posting or confirmed moderation history, and staff can silence it from the queue.
That produces a misleading core silence reason and staff history entry.

Distinguish automatic external-evidence enforcement from staff-confirmed action,
and retain the review reference. Do not claim external evidence for local cases.

### Medium: review action ignores the core moderation result

`ReviewableSpamWarden#perform_silence_account` returns a successful rejected review
regardless of `Moderation.silence` returning false. Already-silenced or suspended
accounts take this path, and the action can still be offered when Guardian permits
silencing. The interface should distinguish confirming an existing restriction
from applying a new one; a failed requested change must not silently appear applied.

Define those outcomes explicitly and test concurrent/manual sanction changes.

### Low: allowing a pending account logs the operation twice

`UpdateException#update_exception` first calls `Moderation.allow`, then performs
`allow_account` on pending reviews, which calls `Moderation.allow` again. The
unique review type/target normally limits this to two custom staff log entries.

Resolve the pending review through one canonical action, or separate idempotent
exception mutation from review resolution while logging once.

### Maintenance: user-list integration relies on internal contracts

The visible column uses genuine core outlets and a serializer extension. However,
batch preparation prepends `AdminUserIndexQuery#find_users`, and the frontend
patches `columnCount` and the account controller's query parameters. These are
more sensitive to core changes than a dedicated column registration API.
The current query class has no equivalent batch-enrichment modifier to switch to.

Keep the patches narrow and covered by compatibility tests. A generic upstream
admin-column/batch-enrichment extension point would be a useful contribution;
do not replace batching with per-user serializer queries to remove the prepend.

## Original recommendations and deliberate boundaries

- Replace the activity page's numeric user-ID input with a core user chooser in
  FormKit. This is a usability improvement, not a missing moderation capability.
- Local evidence currently does not produce a scored assessment when the provider
  fails or no identifiers are enabled. Document this coupling; consider a separate
  local-only review path with explicit unavailable external evidence. Preserve the
  rule that local signals cannot automatically silence an account.
- The provider client uses fixed HTTPS endpoints, bounded requests and responses,
  normalized results and core Redis. A custom SFS adapter is justified. Core's
  URL-fetching helpers are not automatically a better fit for this fixed API POST;
  reassess outbound-request protections if configurable destinations are added.
- Core posting validation and rate limits remain authoritative. Historical burst
  and duplicate evidence complement them; do not build a competing posting gate.
- An exemption applies to Spam Warden only. Preserve core sanctions and other spam
  systems, including Discourse AI; do not reinterpret it as universal approval.
- Before implementing Pro analysis, add a tested evidence-contribution contract
  before assessment. The current post-check event occurs after persistence and
  enforcement and is suitable for follow-up work, not changing that assessment.
  Reuse the same core review and moderation boundaries in both tiers.

## Verification after fixes

- Free plugin backend suite: 114 examples, zero failures.
- Affected core admin-list and review-list request tests: 40 examples, zero failures.
- Plugin browser suite: 22 tests, zero failures, including the named user chooser,
  subfolder-prefixed links, column layout and automatic dashboard opening.
- Changed-file lint, translation YAML parsing and core diff whitespace checks pass.

Run core and plugin suites separately: a core review test deliberately resets the
plugin registry and cannot share a plugin test run. The browser suite required a
fresh asset build and a longer startup grace period after intermittent harness
stalls. Final browser seed: `DJTioq0x`.

These checks cover the integration regressions, not live provider effectiveness
or visual review across every theme. No production deployment was performed.
