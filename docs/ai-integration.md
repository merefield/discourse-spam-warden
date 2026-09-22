# AI classifier integration

The free plugin can display existing Discourse AI or extension-provided spam findings alongside Stop Forum
Spam reputation. It does not run a classifier or make additional LLM requests.

## Setup and dashboard

`spam_warden_ai_integration` defaults on. It takes effect when Discourse AI or an installed classifier extension provides an
available log table. Neither Discourse AI nor a paid extension is mandatory. Disable it to stop AI evidence display and review
coordination. Spam Warden works without Discourse AI installed.

Open an admin user page and expand **Spam Warden**. The AI panel shows classification,
explanation, scan time, links to the post and review, and the human review outcome.
Pending, confirmed, rejected, ignored and no human decision are separate states.
The latest AI classification does not replace a human decision. Linked reviews must match
the post and contain a spam score; scans without a review link fall back to the newest
matching spam review, never an unrelated flag. **Refresh AI findings**
loads saved results; it does not ask the model to scan again.

The panel displays up to 10 latest results, one per post, drawn from the latest 100
regular public-topic posts created in the last 30 days, with scans from the same period.
Uncategorized posts are included; private messages and restricted categories are excluded. Deleted posts can appear
when their public topic remains available. Explanations are truncated to 2,000 characters.
This is a bounded account summary, not a complete AI audit log. No findings is not a
clean bill of health. Retained logs remain readable if AI scanning is subsequently disabled.

## Reviews and restrictions

When a reputation check needs review, Spam Warden reuses a pending AI spam review for
that account within the same bounded sample. It attaches its own saved assessment
without modifying the AI flag, classification or review payload. The review shows the
linked Spam Warden evidence, and admins can open the account dashboard from it.

If the account review was created first, a background job scheduled after an AI flag
moves linked assessments to the pending AI review and closes the duplicate account
review as ignored. Its history and destination review ID are retained. A brief overlap
is possible while the job waits. Completed AI reviews are never reopened or reused.
Existing restrictions remain in place; an exemption only reverses a silence still
owned by Spam Warden. Discourse AI keeps its own independent moderation policy.

## Scoring and reporting

AI classifications add **no risk points** and cannot qualify an account for reporting.
When human staff agree with an AI-created spam flag, the existing confirmed-spam rule
counts that post once, using the configured per-post weight (default 85). Staff rejection
adds no confirmed-spam points and does not erase independent reputation evidence.
Existing automatic reassessment eligibility and delays still apply; admins can recheck
older accounts manually to update their saved scores.

A human-confirmed finding offers **Preview account report to Stop Forum Spam**. This
opens the existing account-level preview using its latest eligible confirmed public
post, which may differ from the finding clicked. All existing eligibility checks,
API-key configuration, exact-data preview and explicit admin agreement still apply.
Staff accounts retain their evidence panel but have no reporting action.
Nothing is submitted automatically. See [submission safeguards](submissions.md).

## Privacy and implementation

AI explanations are admin-only. Raw prompts, model payloads and audit-log contents are
not returned by Spam Warden. No AI evidence is copied into its tables or sent to Stop
Forum Spam. Each classifier retains ownership of its logs and retention policy.

The adapter reads `AiSpamLog`, registered [classifier log models](classifier-integration.md), and core `ReviewableFlaggedPost` / `ReviewableScore` records.
Only positive-ID human staff review decisions count as confirmation. Review-list scan
and AI associations are fetched in batches. The reconciliation job uses the same account
mutex as reputation checks and core review transitions for the duplicate's audit history.
Tests exercise actual AI scanner flags with prepared model responses, core human review,
review serialization, standalone operation and the existing reporting preview.
