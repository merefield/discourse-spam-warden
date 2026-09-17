# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::UpdateException do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to allow_values(true, false).for(:allowed) }
    it { is_expected.not_to allow_value(nil).for(:allowed) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:user)
    fab!(:actor, :admin)
    let(:params) { { user_id: user.id, allowed: true } }
    let(:dependencies) { { guardian: actor.guardian } }

    context "with invalid parameters" do
      let(:params) { { user_id: nil, allowed: true } }

      it { is_expected.to fail_a_contract }
    end

    context "without a matching account" do
      let(:params) { { user_id: -999, allowed: true } }

      it { is_expected.to fail_to_find_a_model(:user) }
    end

    context "when an ordinary user requests an exception" do
      fab!(:actor, :user)

      it { is_expected.to fail_a_policy(:can_manage_exception) }
    end

    context "when a moderator requests an exception" do
      fab!(:actor, :moderator)

      it { is_expected.to fail_a_policy(:can_manage_exception) }
    end

    context "when the target is staff" do
      fab!(:user, :admin)

      it { is_expected.to fail_a_policy(:can_manage_exception) }
    end

    context "when an administrator grants an exception" do
      it "records the actor and keeps the action available when checking is disabled" do
        SiteSetting.spam_warden_enabled = false

        expect(result).to run_successfully
        expect(DiscourseSpamWarden::Account.find_by(user: user)).to have_attributes(
          allowed: true,
          allowed_by_id: actor.id,
        )
      end

      it "preserves independent staff sanctions" do
        UserSilencer.new(user, actor, reason: "Independent staff decision").silence

        expect(result).to run_successfully
        expect(user.reload).to be_silenced
      end

      it "releases its own silence and resolves the pending review with one staff log entry" do
        SiteSetting.spam_warden_enabled = true
        SiteSetting.spam_warden_mode = "protect"
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
        scan = DiscourseSpamWarden::Checker.call(user, source: "registration")

        expect { expect(result).to run_successfully }.to change {
          UserHistory.where(custom_type: "spam_warden_allow", acting_user_id: actor.id).count
        }.by(1)
        expect(user.reload).not_to be_silenced
        expect(scan.reviewable.reload).to be_approved
      end
    end

    context "when an administrator removes an exception" do
      let(:params) { { user_id: user.id, allowed: false } }

      before { DiscourseSpamWarden::Moderation.allow(user, actor) }

      it "resumes eligibility without automatically checking or restricting the account" do
        expect(result).to run_successfully
        expect(DiscourseSpamWarden::Account.find_by(user: user)).to have_attributes(
          allowed: false,
          allowed_by_id: nil,
        )
        expect(user.reload).not_to be_silenced
        expect(DiscourseSpamWarden::Scan.where(user: user)).to be_empty
      end
    end
  end
end
