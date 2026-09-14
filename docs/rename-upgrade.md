# Upgrade from Spam Guard to Spam Warden

Version 0.2.0 renames the plugin, Ruby namespace, routes, JavaScript modules,
settings, CSS classes, extension events and database tables to Spam Warden.

## Installation and deployment

This is a maintenance-window upgrade, not a rolling deployment. Stop web and
Sidekiq workers, back up the database, install this version, run all migrations
including post-deployment migrations, rebuild assets, then restart both processes.
Do not skip post-deployment migrations: the new code requires the renamed tables.
Do not run old and new versions simultaneously.

The GitHub repository remains `merefield/discourse-spam-guard` until separately
renamed. Clone it into a directory named `discourse-spam-warden`:

```yaml
- git clone https://github.com/merefield/discourse-spam-guard.git discourse-spam-warden
```

Replace the previous clone line and remove the old plugin directory from the
build. Install only one copy. Local development uses `~/code/discourse-spam-warden`
linked into `~/discourse/plugins/discourse-spam-warden`.

## Preserved data

The post-deployment migration renames the accounts, scans and submissions tables
and their indexes without copying or dropping records. Account exemptions,
plugin-owned silence history, saved scores, review associations and submission
history retain their IDs. Existing setting overrides, including the submission
API key, move from `spam_guard_*` to `spam_warden_*`. Conflicting setting names
cause the transaction to fail rather than overwrite a value.

Reviewable types and sources, review reasons and structured staff action names
are migrated. Historical free-text log messages and saved assessment snapshots
are retained as recorded. The original migration files remain unchanged so that
both existing sites and fresh installs follow the same migration history.

Old queued job names have compatibility handlers; they execute the new code and
retain submission duplicate protection. The old Ruby module remains an alias for
the separately installed Pro skeleton. New jobs and extension events use Warden.
The Pro skeleton's own settings are not migrated by the free plugin.

Transient lookup caches expire naturally and new checks use the Warden cache
namespace. Reopen the dashboard after upgrading: old URLs, query parameters and
unsigned UI state are not migrated, and an outstanding report preview must be
opened again because its signing purpose has changed.

Rollback requires restoring the pre-upgrade database backup and previous code;
do not run the old code against renamed tables. Existing uncertain submissions
remain uncertain and must not be resent merely because of the rename.
