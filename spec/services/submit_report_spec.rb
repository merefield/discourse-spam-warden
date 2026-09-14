# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::SubmitReport do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_presence_of(:token) }
    it { is_expected.to validate_length_of(:token).is_at_most(4096) }
    it { is_expected.to allow_value(true).for(:confirmed) }
    it { is_expected.not_to allow_values(false, nil).for(:confirmed) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params: params, **dependencies) }

    fab!(:acting_user, :admin)
    fab!(:user)
    fab!(:post) { Fabricate(:spam_warden_confirmed_post, user: user) }
    let(:candidate) { DiscourseSpamWarden::SubmissionCandidate.latest(user) }
    let(:token) { candidate.preview_token(acting_user) }
    let(:params) { { user_id: user.id, token: token, confirmed: true } }
    let(:dependencies) { { guardian: acting_user.guardian } }

    before do
      SiteSetting.spam_warden_submissions_enabled = true
      SiteSetting.spam_warden_submission_api_key = "test-submission-key"
      Jobs.run_later!
    end

    context "without explicit confirmation" do
      let(:params) { super().merge(confirmed: false) }
      it { is_expected.to fail_a_contract }
    end

    context "with a moderator" do
      fab!(:acting_user, :moderator)
      it { is_expected.to fail_a_policy(:can_submit) }
    end

    context "with the system actor" do
      fab!(:acting_user) { Discourse.system_user }
      it { is_expected.to fail_a_policy(:can_submit) }
    end

    context "without configuration" do
      before { SiteSetting.spam_warden_submission_api_key = "" }
      it { is_expected.to fail_a_policy(:configured) }
    end

    context "without a user" do
      let(:params) { super().merge(user_id: -999) }
      it { is_expected.to fail_to_find_a_model(:user) }
    end

    context "with an invalid preview" do
      let(:token) { "invalid-token" }
      it { is_expected.to fail_to_find_a_model(:candidate) }
    end

    context "with an approved preview" do
      it "reserves one report, schedules delivery and audits approval" do
        expect_enqueued_with(job: :spam_warden_submit) { expect(result).to run_successfully }
        report = DiscourseSpamWarden::Submission.find_by!(user: user)
        expect(report).to have_attributes(
          status: "pending",
          actor_id: acting_user.id,
          post_id: post.id,
          attempts: 0,
        )
        expect(UserHistory.where(acting_user_id: acting_user.id).last.custom_type).to eq(
          "spam_warden_submit_approved",
        )
      end
    end
  end
end
