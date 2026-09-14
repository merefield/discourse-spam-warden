# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::Moderation do
  describe ".allow" do
    fab!(:user)
    fab!(:admin)

    it "rejects non-staff actors without creating an exception" do
      actor = Fabricate(:user)

      expect { described_class.allow(user, actor) }.to raise_error(Discourse::InvalidAccess)
      expect(DiscourseSpamWarden::Account.where(user: user)).to be_empty
    end

    it "protects staff accounts" do
      expect { described_class.allow(admin, admin) }.to raise_error(Discourse::InvalidAccess)
      expect(DiscourseSpamWarden::Account.where(user: admin)).to be_empty
    end

    it "rejects moderators without changing exemptions or releasing a silence" do
      moderator = Fabricate(:moderator)
      UserSilencer.new(user, admin, reason: "Staff restriction").silence

      expect { described_class.allow(user, moderator) }.to raise_error(Discourse::InvalidAccess)
      expect(DiscourseSpamWarden::Account.where(user: user)).to be_empty
      expect(user.reload).to be_silenced
      expect(
        UserHistory.where(custom_type: "spam_warden_allow", acting_user_id: moderator.id),
      ).to be_empty
    end
  end
end
