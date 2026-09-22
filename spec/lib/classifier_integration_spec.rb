# frozen_string_literal: true

module DiscourseSpamWarden
  class TestClassifierLog < ActiveRecord::Base
    self.table_name = "warden_test_classifier_logs"
  end

  class OtherTestClassifierLog < ActiveRecord::Base
    self.table_name = "warden_other_test_classifier_logs"
  end

  class BrokenTestClassifierLog < OtherTestClassifierLog
    default_scope { where("missing_classifier_column = 1") }
  end

  module ClassifierSpecHelpers
    def create_log(target = post, model: DiscourseSpamWarden::TestClassifierLog, **attributes)
      model.create!(
        post_id: target.id,
        is_spam: true,
        reason: "Classifier finding",
        created_at: Time.current,
        **attributes,
      )
    end
  end
end

RSpec.describe DiscourseSpamWarden::AiIntegration do
  include DiscourseSpamWarden::ClassifierSpecHelpers
  fab!(:admin)
  fab!(:user)
  fab!(:post) { Fabricate(:post, user: user) }
  let(:plugin) { Plugin::Instance.new }
  let(:providers) { [DiscourseSpamWarden::TestClassifierLog] }
  let(:model_modifier) { proc { |models| models + providers } }
  let(:bot_modifier) { proc { |ids| ids + [Discourse.system_user.id] } }

  around do |example|
    original = Object.send(:remove_const, :AiSpamLog) if Object.const_defined?(:AiSpamLog)
    example.run
  ensure
    Object.const_set(:AiSpamLog, original) if original
  end

  before do
    SiteSetting.ai_spam_detection_enabled = false if SiteSetting.respond_to?(
      :ai_spam_detection_enabled,
    )
    plugin.stubs(:enabled?).returns(true)
    [
      DiscourseSpamWarden::TestClassifierLog,
      DiscourseSpamWarden::OtherTestClassifierLog,
    ].each do |model|
      DB.exec(<<~SQL)
        CREATE TABLE #{model.table_name} (
          id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          post_id bigint NOT NULL,
          reviewable_id bigint,
          is_spam boolean NOT NULL,
          reason text,
          error text,
          created_at timestamp NOT NULL
        )
      SQL
      model.reset_column_information
    end
    DiscoursePluginRegistry.register_modifier(
      plugin,
      :spam_warden_classifier_log_models,
      &model_modifier
    )
    DiscoursePluginRegistry.register_modifier(
      plugin,
      :spam_warden_classifier_bot_ids,
      &bot_modifier
    )
  end

  after do
    DiscoursePluginRegistry.unregister_modifier(
      plugin,
      :spam_warden_classifier_log_models,
      &model_modifier
    )
    DiscoursePluginRegistry.unregister_modifier(
      plugin,
      :spam_warden_classifier_bot_ids,
      &bot_modifier
    )
  end

  describe ".snapshot with only extension classifiers" do
    it "shows findings only to admins and preserves human review outcomes" do
      expect(defined?(::AiSpamLog)).to be_nil
      result =
        PostActionCreator.new(
          Discourse.system_user,
          post,
          PostActionType.types[:spam],
          queue_for_review: true,
        ).perform
      log = create_log(reviewable_id: result.reviewable.id)
      expect(described_class.snapshot(user, guardian: admin.guardian)["entries"].sole).to include(
        "post_id" => post.id,
        "reason" => log.reason,
        "outcome" => "pending",
      )
      expect(described_class.snapshot(user, guardian: user.guardian)).to be_nil
      expect(described_class.snapshot(user, guardian: Fabricate(:moderator).guardian)).to be_nil
      result.reviewable.perform(admin, :disagree)
      expect(
        described_class.snapshot(user, guardian: admin.guardian)["entries"].sole["outcome"],
      ).to eq("rejected")
    end

    it "chooses the newest finding per post before applying the global limit" do
      providers << DiscourseSpamWarden::OtherTestClassifierLog
      targets = 11.times.map { Fabricate(:post, user: user, topic: post.topic) }
      targets.each_with_index do |target, index|
        create_log(target, created_at: (30 - index).minutes.ago)
        create_log(
          target,
          model: DiscourseSpamWarden::OtherTestClassifierLog,
          created_at: (20 - index).minutes.ago,
          is_spam: false,
          reason: "Newer finding",
        )
      end
      entries = described_class.snapshot(user, guardian: admin.guardian)["entries"]
      expect(entries.map { |entry| entry["post_id"] }).to eq(targets.last(10).reverse.map(&:id))
      expect(entries.map { |entry| entry["is_spam"] }).to eq([false] * 10)
    end

    it "excludes restricted posts and old logs" do
      restricted =
        Fabricate(
          :post,
          user: user,
          topic: Fabricate(:topic, category: Fabricate(:private_category, group: Group[:staff])),
        )
      create_log(restricted)
      create_log(created_at: 31.days.ago)
      expect(described_class.snapshot(user, guardian: admin.guardian)["entries"]).to eq([])
    end
  end

  describe "review coordination through both modifiers" do
    it "reuses classifier reviews and reconciles an earlier account review without confirming spam" do
      duplicate =
        ReviewableSpamWarden.needs_review!(
          target: user,
          created_by: Discourse.system_user,
          payload: {
          },
        )
      result =
        PostActionCreator.new(
          Discourse.system_user,
          post,
          PostActionType.types[:spam],
          queue_for_review: true,
        ).perform
      create_log(reviewable_id: result.reviewable.id)
      expect(described_class.pending_review(user)).to eq(result.reviewable)
      expect(described_class.ai_review_ids([result.reviewable])).to eq([result.reviewable.id])
      expect(Jobs::SpamWardenReconcileAi.jobs.last["args"].first["user_id"]).to eq(user.id)
      Jobs::SpamWardenReconcileAi.new.execute(user_id: user.id)
      expect(duplicate.reload).to be_ignored
      expect(result.reviewable.reload).to be_pending
      expect(DiscourseSpamWarden::LocalSignals.snapshot(user)["history_points"]).to eq(0)
    end
  end

  describe "provider failure isolation" do
    it "keeps other providers available when a table probe fails" do
      providers << DiscourseSpamWarden::OtherTestClassifierLog
      Rails
        .logger
        .expects(:warn)
        .with(
          "Spam Warden classifier provider DiscourseSpamWarden::OtherTestClassifierLog unavailable (StandardError)",
        )
        .at_least_once
      DiscourseSpamWarden::OtherTestClassifierLog.stubs(:table_exists?).raises(
        StandardError,
        "private exception content",
      )
      log = create_log
      expect(
        described_class.snapshot(user, guardian: admin.guardian)["entries"].sole["reason"],
      ).to eq(log.reason)
    end

    it "contains SQL failures without aborting an enclosing transaction or losing healthy findings" do
      providers << DiscourseSpamWarden::BrokenTestClassifierLog
      create_log
      ActiveRecord::Base.transaction do
        expect(described_class.snapshot(user, guardian: admin.guardian)["entries"].length).to eq(1)
        expect(described_class.pending_review(user)).to be_nil
        review = Fabricate(:reviewable_flagged_post, target: post, target_created_by: user)
        expect(described_class.ai_review_ids([review])).to eq([])
        expect(User.exists?(user.id)).to eq(true)
      end
    end
  end

  context "when the model registry callback raises" do
    let(:model_modifier) do
      proc do |models|
        models.clear
        raise "private exception content"
      end
    end

    it "keeps account checks and review lookups usable without a provider" do
      expect(described_class.available?).to eq(false)
      expect(described_class.snapshot(user, guardian: admin.guardian)).to be_nil
      expect(described_class.pending_review(user)).to be_nil
      SiteSetting.spam_warden_enabled = true
      SiteSetting.spam_warden_check_ip = false
      stub_request(:post, "https://api.stopforumspam.org/api").to_return(
        body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json,
      )
      expect(DiscourseSpamWarden::Checker.call(user, source: "manual").status).to eq("checked")
    end

    it "preserves built-in defaults even if a failing callback mutates its input" do
      Object.const_set(:AiSpamLog, DiscourseSpamWarden::TestClassifierLog)
      log = create_log
      expect(
        described_class.snapshot(user, guardian: admin.guardian)["entries"].sole["reason"],
      ).to eq(log.reason)
    ensure
      Object.send(:remove_const, :AiSpamLog)
    end
  end

  context "when a registry returns malformed data" do
    let(:model_modifier) { proc { nil } }
    it "treats the optional classifier as unavailable" do
      expect(described_class.available?).to eq(false)
    end
  end

  context "when the bot-ID callback raises" do
    let(:bot_modifier) { proc { raise "private exception content" } }
    it "allows core flag creation and skips unavailable reconciliation" do
      result =
        PostActionCreator.new(
          Discourse.system_user,
          post,
          PostActionType.types[:spam],
          queue_for_review: true,
        ).perform
      expect(result).to be_success
      expect(Jobs::SpamWardenReconcileAi.jobs).to be_empty
      create_log(reviewable_id: result.reviewable.id)
      expect(described_class.pending_review(user)).to eq(result.reviewable)
    end
  end

  context "when the bot-ID callback returns malformed IDs" do
    let(:bot_modifier) { proc { |ids| ids + [nil, "-1", {}, 1, Discourse.system_user.id] } }
    it "retains valid negative integer IDs" do
      result =
        PostActionCreator.new(
          Discourse.system_user,
          post,
          PostActionType.types[:spam],
          queue_for_review: true,
        ).perform
      expect(result).to be_success
      expect(Jobs::SpamWardenReconcileAi.jobs.last["args"].first["user_id"]).to eq(user.id)
    end
  end
end
