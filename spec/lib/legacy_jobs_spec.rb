# frozen_string_literal: true

RSpec.describe Jobs::SpamGuardSubmit do
  it "executes a legacy submission job without resending an uncertain report" do
    user = Fabricate(:user)
    admin = Fabricate(:admin)
    report =
      DiscourseSpamWarden::Submission.create!(
        user: user,
        actor: admin,
        post_id: 1,
        reviewable_id: 1,
        fingerprint: "saved-fingerprint",
        status: "unknown",
        approved_at: Time.current,
      )

    Jobs::SpamGuardSubmit.new.execute(submission_id: report.id)

    expect(report.reload.status).to eq("unknown")
    expect(a_request(:post, DiscourseSpamWarden::SubmissionClient::ENDPOINT)).not_to have_been_made
  end
end
