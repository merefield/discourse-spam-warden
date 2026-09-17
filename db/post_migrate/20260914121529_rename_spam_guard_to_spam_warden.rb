# frozen_string_literal: true

class RenameSpamGuardToSpamWarden < ActiveRecord::Migration[8.0]
  def up
    %w[accounts scans submissions].each do |suffix|
      rename_table "spam_guard_#{suffix}", "spam_warden_#{suffix}"
    end
    %w[latest source_latest].each do |suffix|
      rename_index :spam_warden_scans,
                   "idx_spam_guard_scans_#{suffix}",
                   "idx_spam_warden_scans_#{suffix}"
    end

    # Fail atomically rather than overwrite separately configured Warden settings.
    execute <<~SQL
      UPDATE site_settings
      SET name = regexp_replace(name, '^spam_guard_', 'spam_warden_')
      WHERE starts_with(name, 'spam_guard_') AND NOT starts_with(name, 'spam_guard_pro_')
    SQL
    execute <<~SQL
      UPDATE reviewables SET type = 'ReviewableSpamWarden'
      WHERE type = 'ReviewableSpamGuard'
    SQL
    execute <<~SQL
      UPDATE reviewables SET type_source = 'discourse-spam-warden'
      WHERE type_source = 'discourse-spam-guard'
    SQL
    execute <<~SQL
      UPDATE reviewable_scores SET reason = 'spam_warden'
      WHERE reason = 'spam_guard'
    SQL
    execute <<~SQL
      UPDATE user_histories SET custom_type = regexp_replace(custom_type, '^spam_guard_', 'spam_warden_')
      WHERE custom_type IN ('spam_guard_allow', 'spam_guard_remove_exception', 'spam_guard_submit_approved', 'spam_guard_submission_preview')
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
