# Reporting confirmed spam to Stop Forum Spam

Individual reporting is part of the free plugin. Reporting is disabled by default.
Enable `spam_guard_submissions_enabled` and set the secret
`spam_guard_submission_api_key` in admin site settings. This key is for reporting;
ordinary reputation lookups do not require it. Reporting has its own controls and
does not depend on the lookup enable switch or identifier lookup settings.
The plugin UI stays registered when lookups are disabled so admins can report
spam, inspect retained evidence and manage recovery. Lookup services and event
handlers still enforce the lookup switch explicitly.

Open an account's admin Spam Guard dashboard and choose the report preview.
The confirmation dialog shows the destination and exact username, email, registration IP and evidence that
will be transmitted. Evidence contains the public post URL and up to 2,000
characters of its raw content. Review it for unrelated sensitive information;
do not approve a report containing material that should not be shared. Check the
explicit approval box and submit, or cancel without sending anything. The dialog
also discloses server-side API key authentication and the JSON response request;
the secret key is never sent to the browser. Preview approval expires after ten minutes.

## Eligibility and permissions

Only human admins can preview or approve reports. A human staff member must have
agreed with a spam flag on that account's post within the last 30 days. Automated
reviews, unresolved flags, risk scores and existing external reports cannot
qualify an account. The preview searches the ten most recent qualifying reviews.

The account must be active, email-confirmed, non-staged, non-staff and not exempt.
The post must belong to an ordinary topic in a publicly readable category.
Private messages and restricted categories are excluded. Deleted spam posts can
still provide evidence when their original topic and category qualify. A public
registration IP is required. Core's IP exclusions are applied, with additional
multicast, documentation and transition-range exclusions; IPv6 must be ordinary
global unicast (2000::/3). IPv4-mapped addresses are checked as IPv4. These
conservative checks also respect the core `blocked_ip_blocks` setting. The
[IPv6 special-purpose registry](https://www.iana.org/assignments/iana-ipv6-special-registry/)
is the reference for the additional documentation and transition exclusions.
Discourse does not retain a per-post IP address.

A signed preview binds approval to the administrator, account and exact payload.
The server reconstructs it rather than accepting identifiers or evidence from
the browser. Eligibility and the fingerprint are rechecked on approval and again
immediately before delivery. Delivery approval expires after one hour. Changes
to the account, evidence, permissions or settings can cancel a queued report.

## Delivery and recovery

Reports run through Sidekiq. A unique per-account record and row locking prevent
concurrent approvals from sending duplicate reports. Pending, sending, submitted
and uncertain records cannot be resubmitted.

Only failures establishing a connection are retried automatically, at most three
attempts, one minute apart. An explicit provider rejection or exhausted connection
attempts permit a fresh preview and approval. Timeouts after connecting, unexpected
responses and worker interruption during delivery are marked uncertain and are
never blindly retried. Check with Stop Forum Spam before taking further action.
A recovery job handles lost queued jobs and stale in-flight records every five
minutes. The dashboard refresh button retrieves the latest status.

Requests use HTTPS, form encoding, bounded timeouts and a bounded response size.
Redirects are not followed. HTTP 200 with an empty body (the documented legacy
success response) or an explicit successful JSON response is recorded as submitted.
Other HTTP statuses and unrecognised responses remain uncertain. Existing uncertain
records are not automatically reclassified because their response bodies were not retained. Provider bodies and credentials are not copied into local errors.
Automated tests mock the provider; they do not verify live credential acceptance
or send real reports.

## Audit, retention and correction

History displays each approving administrator’s current username with a link to their
admin user page. Stored actor IDs remain unchanged; deleted accounts display their ID.

The account retains one compact submission record: internal account, actor, post
and review IDs, a payload hash, status, attempt count, timestamps and the last 20
status events. Raw identifiers, evidence and API credentials are not stored in
that record. Preview and approval also create staff action log entries containing
internal IDs. The API key remains a secret site setting.

Submission records are retained independently of scan retention to prevent repeat
reporting. Account deletion and anonymization remove them. An already transmitted
report cannot be recalled by deleting local data, allowing the account or disabling
reporting. A request already in flight may finish despite a concurrent local
change. Corrections or removal of external reports must be handled with Stop Forum
Spam. Removing local records also removes their duplicate protection.

Bulk approval, campaign analysis, evidence assembly and advanced reporting
workflows remain potential Pro features. Core individual reporting, its approval
safeguards and delivery recovery remain free.
