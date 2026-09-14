# frozen_string_literal: true

require_relative "../../db/post_migrate/20260914121529_rename_spam_guard_to_spam_warden"

RSpec.describe RenameSpamGuardToSpamWarden do
  it "preserves records, settings and review identities across the rename" do
    connection = ActiveRecord::Base.connection
    user = Fabricate(:user)
    admin = Fabricate(:admin)
    account =
      DiscourseSpamWarden::Account.create!(user: user, allowed: true, allowed_by_id: admin.id)
    review = ReviewableSpamWarden.needs_review!(target: user, created_by: admin)
    scan =
      DiscourseSpamWarden::Scan.create!(
        user: user,
        reviewable_id: review.id,
        source: "manual",
        status: "checked",
        decision: "review",
        policy: {
          "assessment" => {
            "score" => 85,
          },
        },
      )
    report =
      DiscourseSpamWarden::Submission.create!(
        user: user,
        actor: admin,
        post_id: 1,
        reviewable_id: review.id,
        fingerprint: "saved-fingerprint",
        status: "unknown",
        approved_at: Time.current,
        events: [{ "actor_id" => admin.id, "status" => "unknown" }],
      )
    connection.execute(<<~SQL)
      INSERT INTO site_settings (name, data_type, value, created_at, updated_at)
      VALUES ('spam_guard_submission_api_key', 1, 'preserved-secret', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
             ('spam_guard_email_report_points', 3, '12', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL

    %w[accounts scans submissions].each do |suffix|
      connection.rename_table "spam_warden_#{suffix}", "spam_guard_#{suffix}"
    end
    %w[latest source_latest].each do |suffix|
      connection.rename_index :spam_guard_scans,
                              "idx_spam_warden_scans_#{suffix}",
                              "idx_spam_guard_scans_#{suffix}"
    end
    connection.execute(
      "UPDATE site_settings SET name = replace(name, 'spam_warden_', 'spam_guard_') WHERE starts_with(name, 'spam_warden_')",
    )
    connection.execute(
      "UPDATE reviewables SET type = 'ReviewableSpamGuard', type_source = 'discourse-spam-guard' WHERE id = #{review.id}",
    )

    described_class.new.up

    expect(account.reload).to have_attributes(allowed: true, allowed_by_id: admin.id)
    expect(scan.reload.policy).to eq("assessment" => { "score" => 85 })
    expect(report.reload).to have_attributes(status: "unknown", fingerprint: "saved-fingerprint")
    expect(report.events).to eq([{ "actor_id" => admin.id, "status" => "unknown" }])
    expect(Reviewable.find(review.id)).to be_a(ReviewableSpamWarden)
    expect(Reviewable.find(review.id).type_source).to eq("discourse-spam-warden")
    expect(
      connection.select_value(
        "SELECT value FROM site_settings WHERE name = 'spam_warden_submission_api_key'",
      ),
    ).to eq("preserved-secret")
    expect(
      connection.select_value(
        "SELECT value FROM site_settings WHERE name = 'spam_warden_email_report_points'",
      ),
    ).to eq("12")
    expect(connection.table_exists?(:spam_guard_accounts)).to eq(false)
    expect(connection.indexes(:spam_warden_scans).map(&:name)).to include(
      "idx_spam_warden_scans_latest",
      "idx_spam_warden_scans_source_latest",
    )
  end
end
