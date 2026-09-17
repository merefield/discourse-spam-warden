# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::Submission do
  fab!(:user)
  fab!(:admin)
  fab!(:post) { Fabricate(:spam_warden_confirmed_post, user: user) }

  before do
    described_class.reserve(DiscourseSpamWarden::SubmissionCandidate.latest(user), admin)
    SiteSetting.spam_warden_enabled = false
  end

  describe "account anonymization" do
    it "removes local submission history even while checks are disabled" do
      UserAnonymizer.make_anonymous(user, admin)
      expect(described_class.where(user_id: user.id)).to be_empty
    end
  end

  describe "account deletion" do
    it "removes submission history immediately" do
      UserDestroyer.new(admin).destroy(user, delete_posts: true)
      expect(described_class.where(user_id: user.id)).to be_empty
    end
  end
end
