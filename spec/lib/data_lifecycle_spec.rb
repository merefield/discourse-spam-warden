# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::Scan do
  fab!(:user)
  fab!(:admin)

  before do
    SiteSetting.spam_warden_enabled = true
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

  describe ".expire!" do
    it "removes expired evidence while retaining unresolved reviews and recent checks" do
      expired = DiscourseSpamWarden::Checker.call(user, source: "registration")
      expired.update!(created_at: 31.days.ago)
      recent = DiscourseSpamWarden::Checker.call(user, source: "recheck")
      SiteSetting.spam_warden_mode = "review"
      pending = DiscourseSpamWarden::Checker.call(user, source: "manual")
      expect(pending).to have_attributes(status: "checked", decision: "review", error_code: nil)
      pending.update!(created_at: 31.days.ago)
      expect(pending.reviewable).to be_pending

      described_class.expire!

      expect(described_class.where(user: user).pluck(:id)).to contain_exactly(recent.id, pending.id)
    end
  end

  describe "account anonymization" do
    it "removes reputation history and exceptions when the account is anonymized" do
      DiscourseSpamWarden::Checker.call(user, source: "registration")
      DiscourseSpamWarden::Moderation.allow(user, admin)
      SiteSetting.spam_warden_enabled = false

      UserAnonymizer.make_anonymous(user, admin)

      expect(described_class.where(user: user)).to be_empty
      expect(DiscourseSpamWarden::Account.where(user: user)).to be_empty
    end
  end

  describe "account deletion" do
    it "removes evidence and exceptions immediately while checking is disabled" do
      DiscourseSpamWarden::Checker.call(user, source: "registration")
      DiscourseSpamWarden::Moderation.allow(user, admin)
      SiteSetting.spam_warden_enabled = false

      UserDestroyer.new(admin).destroy(user)

      expect(described_class.where(user_id: user.id)).to be_empty
      expect(DiscourseSpamWarden::Account.where(user_id: user.id)).to be_empty
    end
  end
end
