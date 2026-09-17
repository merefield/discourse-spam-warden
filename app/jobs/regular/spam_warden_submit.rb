# frozen_string_literal: true

module Jobs
  class SpamWardenSubmit < ::Jobs::Base
    def execute(args)
      report = DiscourseSpamWarden::Submission.find_by(id: args[:submission_id])
      return unless report
      candidate = nil
      report.with_lock do
        return unless report.status == "pending"
        return if report.last_attempt_at && report.last_attempt_at > 1.minute.ago
        candidate = report.candidate
        unless candidate
          report.finish!("cancelled", "eligibility_changed")
          return
        end
        report.attempts += 1
        report.last_attempt_at = Time.current
        report.finish!("sending")
      end
      state, code = DiscourseSpamWarden::SubmissionClient.new.submit(candidate.payload)
      report.with_lock do
        return unless report.status == "sending"
        state = "failed" if state == "pending" &&
          report.attempts >= DiscourseSpamWarden::Submission::MAX_ATTEMPTS
        report.finish!(state, code)
      end
      Jobs.enqueue_in(1.minute, :spam_warden_submit, submission_id: report.id) if state == "pending"
    end
  end
end
