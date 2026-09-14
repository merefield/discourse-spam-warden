# frozen_string_literal: true

RSpec.describe "Spam Warden populated query profile" do
  it "profiles synthetic data inside the test transaction" do
    SiteSetting.spam_warden_local_signals = true
    users = Fabricate.times(10, :user)
    admin = Fabricate(:admin)
    topics = users.map { |user| Fabricate(:topic, user: user) }
    users.zip(topics).each { |user, topic| DB.exec(<<~SQL, user_id: user.id, topic_id: topic.id) }
        INSERT INTO posts (user_id, topic_id, post_number, raw, cooked, created_at, updated_at, last_version_at)
        SELECT :user_id, :topic_id, sequence, repeat('Substantial repeated test content. ', 60), '',
               now() - sequence * interval '1 second', now(), now()
        FROM generate_series(1, 1000) AS sequence
      SQL
    DB.exec(<<~SQL, ids: users.map(&:id))
      INSERT INTO spam_warden_scans (user_id, source, status, decision, action_taken, evidence, policy, created_at, updated_at)
      SELECT account_id, 'activity', 'checked', 'allow', 'none', '{}', '{}',
             now() - sequence * interval '1 minute', now()
      FROM unnest(ARRAY[:ids]) AS account_id CROSS JOIN generate_series(1, 10000) AS sequence
    SQL
    DB.exec(<<~SQL, ids: users.map(&:id), admin: admin.id)
      INSERT INTO reviewables (type, status, target_id, target_type, target_created_by_id, created_by_id, created_at, updated_at)
      SELECT 'ReviewableFlaggedPost', 1, id, 'Post', user_id, :admin, now(), now()
      FROM posts WHERE user_id IN (:ids)
    SQL
    DB.exec(<<~SQL, ids: users.map(&:id), admin: admin.id)
      INSERT INTO reviewable_scores (reviewable_id, user_id, reviewable_score_type, status, reviewed_by_id, reviewed_at, created_at, updated_at)
      SELECT reviewables.id, :admin, 8, 1, :admin, now(), now(), now()
      FROM reviewables CROSS JOIN generate_series(1, 10) AS sequence
      WHERE target_created_by_id IN (:ids)
    SQL
    %w[
      posts
      topics
      categories
      users
      reviewables
      reviewable_scores
      spam_warden_scans
    ].each { |table| DB.exec("ANALYZE #{table}") }
    connection = ActiveRecord::Base.connection
    report =
      lambda do |name, sql, binds = []|
        plan =
          connection
            .exec_query("EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) #{sql}", "profile", binds)
            .rows
            .flatten
        puts "\n#{name}\n#{plan.join("\n")}"
      end
    old_list =
      DiscourseSpamWarden::Scan
        .where(user_id: users.map(&:id))
        .select("DISTINCT ON (user_id) user_id, status, decision, created_at, policy")
        .order(:user_id, created_at: :desc, id: :desc)
    report.call("OLD LIST: 100,000 scans / 10 accounts", old_list.to_sql)
    captured = []
    subscriber =
      lambda do |_name, _start, _finish, _id, payload|
        if payload[:sql].start_with?("SELECT") && payload[:name] != "SCHEMA"
          captured << [payload[:sql], payload[:binds]]
        end
      end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      expect(DiscourseSpamWarden::Scan.latest_for_users(users.map(&:id)).size).to eq(10)
      DiscourseSpamWarden::LocalSignals.snapshot(users.first)
    end
    captured.each_with_index do |(sql, binds), index|
      report.call("NEW QUERY #{index + 1}", sql, binds)
    end
    old_history =
      ReviewableFlaggedPost
        .approved
        .where(target_created_by: users.first)
        .joins(:reviewable_scores)
        .where(
          reviewable_scores: {
            status: 1,
            reviewable_score_type: 8,
            reviewed_by_id: User.where("id > 0 AND (admin OR moderator)").select(:id),
            reviewed_at: 30.days.ago..Time.current,
          },
        )
        .distinct
        .limit(3)
        .select(:target_id)
    report.call("OLD HISTORY: 1,000 reviewed posts / 10,000 flags for account", old_history.to_sql)
    DB.exec(<<~SQL, user_id: users.first.id)
      UPDATE reviewable_scores SET reviewed_at = now() - interval '31 days'
      WHERE reviewable_id IN (SELECT id FROM reviewables WHERE target_created_by_id = :user_id)
    SQL
    DB.exec("ANALYZE reviewable_scores")
    sql, binds = captured.last
    report.call("NEW HISTORY: all 10,000 flags expired", sql, binds)
  end
end
