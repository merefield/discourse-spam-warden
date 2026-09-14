# frozen_string_literal: true

RSpec.describe Jobs::SpamWardenSubmit do
  fab!(:user)
  fab!(:admin)
  fab!(:post) { Fabricate(:spam_warden_confirmed_post, user: user) }
  let(:report) do
    DiscourseSpamWarden::Submission.reserve(
      DiscourseSpamWarden::SubmissionCandidate.latest(user),
      admin,
    )
  end

  before do
    freeze_time
    SiteSetting.spam_warden_submissions_enabled = true
    SiteSetting.spam_warden_submission_api_key = "test-submission-key"
    Jobs.run_later!
  end

  describe "#execute" do
    it "sends once despite repeated approval and duplicate jobs" do
      request =
        stub_request(:post, DiscourseSpamWarden::SubmissionClient::ENDPOINT).to_return(
          body: '{"success":true}',
        )
      described_class.new.execute(submission_id: report.id)
      repeated =
        DiscourseSpamWarden::Submission.reserve(
          DiscourseSpamWarden::SubmissionCandidate.latest(user),
          admin,
        )
      expect(repeated.id).to eq(report.id)
      described_class.new.execute(submission_id: repeated.id)
      expect(report.reload).to have_attributes(status: "submitted", attempts: 1)
      expect(request).to have_been_requested.once
    end

    it "limits preconnection retries to three attempts" do
      request =
        stub_request(:post, DiscourseSpamWarden::SubmissionClient::ENDPOINT).to_raise(
          Net::OpenTimeout,
        )
      expect_enqueued_with(job: :spam_warden_submit) do
        described_class.new.execute(submission_id: report.id)
      end
      2.times do
        freeze_time 2.minutes.from_now
        described_class.new.execute(submission_id: report.id)
      end
      expect(report.reload).to have_attributes(
        status: "failed",
        attempts: 3,
        error_code: "connection_failed",
      )
      described_class.new.execute(submission_id: report.id)
      expect(request).to have_been_requested.times(3)
    end

    it "leaves uncertain deliveries blocked without retrying" do
      request =
        stub_request(:post, DiscourseSpamWarden::SubmissionClient::ENDPOINT).to_raise(
          Net::ReadTimeout,
        )
      report
      expect_not_enqueued_with(job: :spam_warden_submit) do
        described_class.new.execute(submission_id: report.id)
      end
      described_class.new.execute(submission_id: report.id)
      expect(report.reload.status).to eq("unknown")
      expect(request).to have_been_requested.once
    end

    it "cancels when staff exempt an account before dispatch" do
      report
      DiscourseSpamWarden::Moderation.allow(user, admin)
      described_class.new.execute(submission_id: report.id)
      expect(report.reload).to have_attributes(
        status: "cancelled",
        attempts: 0,
        error_code: "eligibility_changed",
      )
    end

    it "cancels when evidence changes or the actor loses access" do
      report
      post.update!(raw: "Changed evidence after approval must not be sent externally.")
      described_class.new.execute(submission_id: report.id)
      expect(report.reload.status).to eq("cancelled")
      new_report =
        DiscourseSpamWarden::Submission.reserve(
          DiscourseSpamWarden::SubmissionCandidate.latest(user),
          admin,
        )
      admin.update!(admin: false)
      described_class.new.execute(submission_id: new_report.id)
      expect(new_report.reload.status).to eq("cancelled")
    end

    it "cancels expired approvals" do
      report
      freeze_time 61.minutes.from_now
      described_class.new.execute(submission_id: report.id)
      expect(report.reload.status).to eq("cancelled")
    end

    it "recovers abandoned delivery as uncertain without replaying it" do
      report.finish!("sending")
      freeze_time 2.minutes.from_now
      expect_not_enqueued_with(job: :spam_warden_submit) do
        Jobs::SpamWardenSubmissionRecovery.new.execute({})
      end
      expect(report.reload).to have_attributes(status: "unknown", error_code: "delivery_uncertain")
    end
  end
end
