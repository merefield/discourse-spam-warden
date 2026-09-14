# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::Checker do
  describe ".call" do
    fab!(:user)
    fab!(:admin)

    before do
      SiteSetting.spam_warden_enabled = true
      SiteSetting.spam_warden_preset = "balanced"
      SiteSetting.spam_warden_check_ip = false
      stub_request(:post, "https://api.stopforumspam.org/api").to_return(
        body: {
          success: 1,
          email: {
            appears: 1,
            frequency: 20,
            confidence: 99,
            lastseen: 1.day.ago.iso8601,
          },
        }.to_json,
      )
    end

    it "records evidence without restrictions in observe mode" do
      scan = described_class.call(user, source: "registration")

      expect(scan).to have_attributes(decision: "silence", action_taken: "none", reviewable_id: nil)
      expect(user.reload).not_to be_silenced
      expect(scan.attributes.to_json).not_to include(user.email)
    end

    it "adds confirmed spam separately from reading reassurance and retains the configured snapshot" do
      SiteSetting.spam_warden_mode = "protect"
      stub_request(:post, "https://api.stopforumspam.org/api").to_return(
        body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json,
      )
      review =
        Fabricate(
          :reviewable_flagged_post,
          target_created_by: user,
          status: :approved,
          reviewable_scores: [],
        )
      Fabricate(
        :reviewable_score,
        reviewable: review,
        reviewable_score_type: ReviewableScore.types[:spam],
        reviewed_by: admin,
        reviewed_at: Time.current,
        status: :agreed,
      )
      user.user_stat.update!(
        topics_entered: 5,
        posts_read_count: 30,
        time_read: 600,
        days_visited: 2,
      )

      original = described_class.call(user, source: "registration")
      expect(original).to have_attributes(decision: "review", action_taken: "review")
      expect(original.policy.dig("assessment", "score")).to eq(85)
      expect(user.reload).not_to be_silenced

      SiteSetting.spam_warden_confirmed_spam_points = 90
      updated = described_class.call(user, source: "manual")
      expect(updated.policy.dig("assessment", "score")).to eq(90)
      expect(updated.policy.dig("weights", "confirmed_spam")).to eq(90)
      expect(original.reload.policy.dig("weights", "confirmed_spam")).to eq(85)
      expect(original.policy.dig("assessment", "score")).to eq(85)

      SiteSetting.spam_warden_confirmed_spam_points = 80
      second_review =
        Fabricate(
          :reviewable_flagged_post,
          target_created_by: user,
          status: :approved,
          reviewable_scores: [],
        )
      Fabricate(
        :reviewable_score,
        reviewable: second_review,
        reviewable_score_type: ReviewableScore.types[:spam],
        reviewed_by: admin,
        reviewed_at: Time.current,
        status: :agreed,
      )
      repeated = described_class.call(user, source: "manual")
      expect(repeated.policy.dig("assessment", "local_signals", "history_points")).to eq(160)
      expect(repeated.policy.dig("assessment", "score")).to eq(100)
      expect(repeated).to have_attributes(decision: "review", action_taken: "review")
      expect(user.reload).not_to be_silenced
    end

    it "queues evidence for review without restricting the account in review mode" do
      SiteSetting.spam_warden_mode = "review"

      scan = described_class.call(user, source: "registration")

      expect(scan.action_taken).to eq("review")
      expect(scan.reviewable).to be_pending
      expect(user.reload).not_to be_silenced
    end

    it "silences strong matches and creates a single review item across repeated jobs" do
      SiteSetting.spam_warden_mode = "protect"

      scan = described_class.call(user, source: "registration")
      repeated = described_class.call(user, source: "registration")

      expect(scan.action_taken).to eq("silenced")
      expect(user.reload).to be_silenced
      expect(repeated.id).to eq(scan.id)
      expect(DiscourseSpamWarden::Scan.where(user: user).count).to eq(1)
      expect(ReviewableSpamWarden.where(target: user).count).to eq(1)
    end

    it "keeps manual checks advisory in protect mode" do
      SiteSetting.spam_warden_mode = "protect"

      scan = described_class.call(user, source: "manual")

      expect(scan.action_taken).to eq("review")
      expect(user.reload).not_to be_silenced
    end

    it "releases its own silence and honors the account exception on recheck" do
      SiteSetting.spam_warden_mode = "protect"
      scan = described_class.call(user, source: "registration")

      DiscourseSpamWarden::Moderation.allow(user, admin, reviewable: scan.reviewable)
      expect(user.reload).not_to be_silenced
      expect { described_class.call(user, source: "recheck") }.not_to change(
        DiscourseSpamWarden::Scan,
        :count,
      )
    end

    it "preserves a later staff sanction when allowing the account" do
      SiteSetting.spam_warden_mode = "protect"
      scan = described_class.call(user, source: "registration")
      UserSilencer.unsilence(user, admin)
      UserSilencer.new(user, admin, reason: "Independent staff decision").silence

      DiscourseSpamWarden::Moderation.allow(user, admin, reviewable: scan.reviewable)

      expect(user.reload).to be_silenced
      expect(DiscourseSpamWarden::Account.find_by(user: user)).to be_allowed
    end

    it "records unknown evidence without restricting the account when the provider is unavailable" do
      SiteSetting.spam_warden_mode = "protect"
      stub_request(:post, "https://api.stopforumspam.org/api").to_timeout

      scan = described_class.call(user, source: "registration")

      expect(scan).to have_attributes(status: "unknown", decision: "unknown", reviewable_id: nil)
      expect(user.reload).not_to be_silenced
    end

    it "excludes staff from automatic checks" do
      expect { described_class.call(admin, source: "registration") }.not_to change(
        DiscourseSpamWarden::Scan,
        :count,
      )
    end

    it "routes strong external matches to review when reading provides meaningful reassurance" do
      SiteSetting.spam_warden_mode = "protect"
      user.user_stat.update!(topics_entered: 3, posts_read_count: 10, time_read: 180)

      scan = described_class.call(user, source: "recheck")

      expect(scan).to have_attributes(decision: "review", action_taken: "review")
      expect(user.reload).not_to be_silenced
      expect(scan.policy["assessment"]).to include("external_decision" => "silence", "score" => 50)
      user.user_stat.update!(time_read: 600)
      expect(scan.reload.policy["assessment"]["engagement"]["reading_seconds"]).to eq(180)
    end

    it "records zero reading as concern without taking action when no external match exists" do
      SiteSetting.spam_warden_mode = "protect"
      user.update!(created_at: 2.hours.ago)
      user.user_stat.update!(topics_entered: 0, posts_read_count: 0, time_read: 0)
      stub_request(:post, "https://api.stopforumspam.org/api").to_return(
        body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json,
      )

      scan = described_class.call(user, source: "recheck")

      expect(scan).to have_attributes(decision: "watch", action_taken: "none", reviewable_id: nil)
      expect(scan.policy["assessment"]).to include("base_score" => 0, "score" => 10)
      expect(user.reload).not_to be_silenced
    end

    it "refreshes activity evidence with a cooldown and only requests review for local signals" do
      freeze_time
      SiteSetting.spam_warden_mode = "protect"
      stub_request(:post, "https://api.stopforumspam.org/api").to_return(
        body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json,
      )
      topics = Fabricate.times(3, :topic)
      5.times do |index|
        Fabricate(
          :post,
          user: user,
          topic: topics[index % 3],
          raw: "An identical substantial post repeated across several public topics.",
        )
      end

      scan = described_class.call(user, source: "activity")
      expect(scan).to have_attributes(decision: "review", action_taken: "review")
      expect(scan.policy["assessment"]["local_signals"]["adjustment"]).to eq(25)
      expect(user.reload).not_to be_silenced
      expect(described_class.call(user, source: "activity").id).to eq(scan.id)

      freeze_time 2.minutes.from_now
      refreshed = described_class.call(user, source: "activity")
      expect(refreshed.id).not_to eq(scan.id)
      expect(ReviewableSpamWarden.where(target: user).count).to eq(1)
    end

    it "ignores pending activity jobs when local signals are disabled or the account is exempt" do
      SiteSetting.spam_warden_local_signals = false
      expect { described_class.call(user, source: "activity") }.not_to change(
        DiscourseSpamWarden::Scan,
        :count,
      )
      SiteSetting.spam_warden_local_signals = true
      DiscourseSpamWarden::Moderation.allow(user, admin)
      expect { described_class.call(user, source: "activity") }.not_to change(
        DiscourseSpamWarden::Scan,
        :count,
      )
    end

    it "collects measurements before acquiring the user row lock" do
      queries = track_sql_queries { described_class.call(user, source: "manual") }
      lock_index = queries.index { |query| query.include?("FOR UPDATE") }
      measurements =
        queries.each_index.select do |index|
          queries[index].match?(/FROM "(?:posts|user_stats|reviewables)"/)
        end

      expect(lock_index).not_to be_nil
      expect(measurements.size).to eq(3)
      expect(measurements).to all(be < lock_index)
    end

    it "preserves an exemption granted while the external check was in progress" do
      stub_request(:post, "https://api.stopforumspam.org/api").to_return do
        DiscourseSpamWarden::Moderation.allow(user, admin)
        { body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json }
      end

      expect { described_class.call(user, source: "manual") }.not_to change(
        DiscourseSpamWarden::Scan,
        :count,
      )
      expect(DiscourseSpamWarden::Account.find_by(user: user)).to be_allowed
    end
  end
end
