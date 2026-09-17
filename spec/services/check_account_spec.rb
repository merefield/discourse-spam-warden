# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::CheckAccount do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:user_id) }
    it do
      is_expected.to validate_inclusion_of(:source).in_array(
        %w[manual registration recheck activity],
      )
    end
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:user)
    fab!(:actor, :admin)
    let(:params) { { user_id: user.id, source: "manual" } }
    let(:dependencies) { { guardian: actor.guardian } }

    before { SiteSetting.spam_warden_enabled = true }

    context "with invalid parameters" do
      let(:params) { { user_id: nil } }

      it { is_expected.to fail_a_contract }
    end

    context "when disabled" do
      before { SiteSetting.spam_warden_enabled = false }

      it { is_expected.to fail_a_policy(:enabled) }
    end

    context "without a matching account" do
      let(:params) { { user_id: -999 } }

      it { is_expected.to fail_to_find_a_model(:user) }
    end

    context "when an ordinary user requests a manual check" do
      fab!(:actor, :user)

      it { is_expected.to fail_a_policy(:can_check_account) }
    end

    context "when a moderator requests a manual check" do
      fab!(:actor, :moderator)

      it { is_expected.to fail_a_policy(:can_check_account) }
    end

    context "when the target is staff" do
      fab!(:user, :admin)

      it { is_expected.to fail_a_policy(:can_check_account) }
    end

    context "when an administrator requests an automated check" do
      let(:params) { { user_id: user.id, source: "registration" } }

      it { is_expected.to fail_a_policy(:can_check_account) }
    end

    context "when an administrator requests an activity check" do
      let(:params) { { user_id: user.id, source: "activity" } }

      it { is_expected.to fail_a_policy(:can_check_account) }
    end

    context "when the system requests an activity check" do
      let(:params) { { user_id: user.id, source: "activity" } }
      let(:dependencies) { { guardian: Discourse.system_user.guardian } }

      before do
        SiteSetting.spam_warden_check_ip = false
        stub_request(:post, "https://api.stopforumspam.org/api").to_return(
          body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json,
        )
      end

      it "records a successful activity check" do
        expect(result).to run_successfully
        expect(result[:scan]).to have_attributes(status: "checked", source: "activity")
      end
    end

    context "when an administrator checks an account" do
      before do
        SiteSetting.spam_warden_check_ip = false
        stub_request(:post, "https://api.stopforumspam.org/api").to_return(
          body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json,
        )
      end

      it "records a successful reputation check" do
        expect(result).to run_successfully
        expect(result[:scan]).to have_attributes(status: "checked", decision: "allow")
      end
    end
  end
end
