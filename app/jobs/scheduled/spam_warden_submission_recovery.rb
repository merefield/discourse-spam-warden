# frozen_string_literal: true

module Jobs
  class SpamWardenSubmissionRecovery < ::Jobs::Scheduled
    every 5.minutes

    def execute(_args)
      DiscourseSpamWarden::Submission
        .where(status: "sending")
        .where("updated_at < ?", 1.minute.ago)
        .limit(100)
        .each do |report|
          report.with_lock do
            report.finish!("unknown", "delivery_uncertain") if report.status == "sending"
          end
        end
      DiscourseSpamWarden::Submission
        .where(status: "pending")
        .where("updated_at < ?", 1.minute.ago)
        .limit(100)
        .pluck(:id)
        .each { |id| Jobs.enqueue(:spam_warden_submit, submission_id: id) }
    end
  end
end
