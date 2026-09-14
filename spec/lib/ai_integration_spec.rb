# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::AiIntegration do
  fab!(:admin)
  fab!(:user)

  describe ".snapshot" do
    it "returns no AI evidence when integration is disabled" do
      SiteSetting.spam_warden_ai_integration = false
      expect(described_class.snapshot(user, guardian: admin.guardian)).to be_nil
      expect(described_class.pending_review(user)).to be_nil
    end

    it "keeps AI evidence private to administrators" do
      expect(described_class.snapshot(user, guardian: Fabricate(:moderator).guardian)).to be_nil
      expect(described_class.snapshot(user, guardian: user.guardian)).to be_nil
    end
  end

  let(:ai_log) do
    DiscourseAi::Completions::Llm.with_prepared_responses(
      [{ spam: true, reason: "Unsolicited commercial promotion" }],
    ) { DiscourseAi::AiModeration::SpamScanner.perform_scan!(post, triggering_user_id: user.id) }
    AiSpamLog.where(post: post).order(id: :desc).first
  end

  if defined?(::AiSpamLog)
    fab!(:llm_model)
    fab!(:post) { Fabricate(:post, user: user) }
    fab!(:spam_setting) { AiModerationSetting.create!(setting_type: :spam, llm_model: llm_model) }

    before do
      SiteSetting.discourse_ai_enabled = true
      SiteSetting.ai_spam_detection_enabled = true
      SiteSetting.spam_warden_enabled = true
      SiteSetting.spam_warden_check_ip = false
      SiteSetting.spam_warden_mode = "review"
      user.email_tokens.update_all(confirmed: true)
      user.update!(registration_ip_address: "8.8.4.4")
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

    describe ".snapshot" do
      it "separates AI classification from human confirmation and reporting eligibility" do
        log = ai_log
        entry = described_class.snapshot(user, guardian: admin.guardian).fetch("entries").sole
        expect(entry).to include(
          "is_spam" => true,
          "outcome" => "pending",
          "reason" => log.reason,
          "reviewable_id" => log.reviewable_id,
        )
        expect(entry.keys).not_to include("payload", "ai_api_audit_log_id")
        expect(DiscourseSpamWarden::LocalSignals.snapshot(user)["history_points"]).to eq(0)
        expect(DiscourseSpamWarden::SubmissionCandidate.latest(user)).to be_nil

        log.reviewable.perform(admin, :agree_and_keep)

        expect(
          described_class.snapshot(user, guardian: admin.guardian)["entries"].sole["outcome"],
        ).to eq("confirmed")
        expect(DiscourseSpamWarden::LocalSignals.snapshot(user)["history_points"]).to eq(85)
        expect(DiscourseSpamWarden::SubmissionCandidate.latest(user).post).to eq(post)
        expect(DiscourseSpamWarden::Submission.count).to eq(0)
      end

      it "retains staff rejection when the latest classification has no review link" do
        log = ai_log
        log.reviewable.perform(admin, :disagree)
        AiSpamLog.create!(
          post: post,
          llm_model: llm_model,
          is_spam: false,
          reason: "Legitimate after editing",
        )

        entry = described_class.snapshot(user, guardian: admin.guardian)["entries"].sole
        expect(entry).to include(
          "is_spam" => false,
          "outcome" => "rejected",
          "reviewable_id" => log.reviewable_id,
        )
        expect(described_class.pending_review(user)).to be_nil
        expect(DiscourseSpamWarden::LocalSignals.snapshot(user)["history_points"]).to eq(0)
        expect(DiscourseSpamWarden::SubmissionCandidate.latest(user)).to be_nil
      end

      it "includes Uncategorized posts in findings and pending review reuse" do
        log = ai_log
        SiteSetting.allow_uncategorized_topics = true
        post.topic.update!(category_id: SiteSetting.uncategorized_category_id)

        entry = described_class.snapshot(user, guardian: admin.guardian)["entries"].sole
        expect(entry).to include("post_id" => post.id, "reviewable_id" => log.reviewable_id)
        expect(described_class.pending_review(user)).to eq(log.reviewable)
      end

      it "ignores unrelated flags when an AI scan has no linked review" do
        review =
          Fabricate(
            :reviewable_flagged_post,
            target: post,
            target_created_by: user,
            reviewable_scores: [],
          )
        Fabricate(
          :reviewable_score,
          reviewable: review,
          reviewable_score_type: ReviewableScore.types[:inappropriate],
        )
        AiSpamLog.create!(post: post, llm_model: llm_model, is_spam: false)

        entry = described_class.snapshot(user, guardian: admin.guardian)["entries"].sole
        expect(entry).to include("outcome" => "unreviewed", "reviewable_id" => nil)
      end

      it "rejects a log link to a different post instead of substituting a review" do
        log = ai_log
        other_post = Fabricate(:post, user: user)
        unrelated = Fabricate(:reviewable_flagged_post, target: other_post, target_created_by: user)
        log.update!(reviewable: unrelated)

        entry = described_class.snapshot(user, guardian: admin.guardian)["entries"].sole
        expect(entry).to include("outcome" => "unreviewed", "reviewable_id" => nil)
      end

      it "excludes private and old posts and limits displayed explanations" do
        private_post =
          Fabricate(:post, user: user, topic: Fabricate(:private_message_topic, user: user))
        restricted_post =
          Fabricate(
            :post,
            user: user,
            topic: Fabricate(:topic, category: Fabricate(:private_category, group: Group[:staff])),
          )
        old_post = Fabricate(:post, user: user, created_at: 31.days.ago)
        [private_post, restricted_post, old_post].each do |excluded_post|
          AiSpamLog.create!(post: excluded_post, llm_model: llm_model, is_spam: true)
        end
        AiSpamLog.create!(
          post: post,
          llm_model: llm_model,
          is_spam: false,
          reason: "a" * 3000,
          payload: "private prompt",
        )
        SiteSetting.discourse_ai_enabled = false

        entries = described_class.snapshot(user, guardian: admin.guardian)["entries"]
        expect(entries.map { |entry| entry["post_id"] }).to eq([post.id])
        expect(entries.sole["reason"].length).to eq(2000)
      end
    end

    describe ".snapshot limits" do
      it "bounds the post sample and returns only the latest ten post assessments" do
        101.times do |index|
          sampled_post = Fabricate(:post, user: user, topic: post.topic)
          AiSpamLog.create!(
            post: sampled_post,
            llm_model: llm_model,
            is_spam: false,
            reason: index.to_s,
          )
        end
        entries = described_class.snapshot(user, guardian: admin.guardian)["entries"]
        expect(entries.map { |entry| entry["reason"] }).to eq((91..100).to_a.reverse.map(&:to_s))
        expect(described_class.latest_logs(user).count).to eq(100)
      end
    end

    describe ".pending_review" do
      it "reuses an AI review without changing its payload or owning its silence" do
        log = ai_log
        payload = log.reviewable.payload.deep_dup
        scan = DiscourseSpamWarden::Checker.call(user, source: "registration")

        expect(scan.reviewable_id).to eq(log.reviewable_id)
        expect(ReviewableSpamWarden.where(target: user)).to be_empty
        expect(log.reviewable.reload.payload).to eq(payload)
        expect(user.reload).to be_silenced
        DiscourseSpamWarden::Moderation.allow(user, admin)
        expect(user.reload).to be_silenced
      end

      it "keeps normal reputation review behavior when integration is disabled" do
        log = ai_log
        SiteSetting.spam_warden_ai_integration = false
        scan = DiscourseSpamWarden::Checker.call(user, source: "manual")
        Jobs::SpamWardenReconcileAi.new.execute(user_id: user.id)

        expect(scan.reload.reviewable).to be_a(ReviewableSpamWarden)
        expect(scan.reviewable).to be_pending
        expect(log.reviewable.reload).to be_pending
        expect(described_class.snapshot(user, guardian: admin.guardian)).to be_nil
      end

      it "creates an independent reputation review after staff dismisses an AI flag" do
        log = ai_log
        log.reviewable.perform(admin, :disagree)

        scan = DiscourseSpamWarden::Checker.call(user, source: "manual")
        expect(scan.reviewable).to be_a(ReviewableSpamWarden)
        expect(log.reviewable.reload).to be_rejected
      end
    end

    describe ".reconcile" do
      it "consolidates an earlier account review into the AI review without confirming spam" do
        scan = DiscourseSpamWarden::Checker.call(user, source: "registration")
        duplicate = scan.reviewable
        log = ai_log
        expect(
          Jobs::SpamWardenReconcileAi.jobs.any? { |job| job["args"].first["user_id"] == user.id },
        ).to eq(true)

        2.times { Jobs::SpamWardenReconcileAi.new.execute(user_id: user.id) }

        expect(scan.reload.reviewable_id).to eq(log.reviewable_id)
        expect(duplicate.reload).to be_ignored
        expect(duplicate.payload["ai_reviewable_id"]).to eq(log.reviewable_id)
        expect(log.reviewable.reload).to be_pending
        expect(DiscourseSpamWarden::LocalSignals.snapshot(user)["history_points"]).to eq(0)
        expect(DiscourseSpamWarden::SubmissionCandidate.latest(user)).to be_nil
        expect(user.reload).to be_silenced
      end
    end
  else
    describe ".snapshot" do
      it "works when Discourse AI is not installed" do
        expect(described_class.snapshot(user, guardian: admin.guardian)).to be_nil
        expect(described_class.pending_review(user)).to be_nil
      end
    end
  end
end
