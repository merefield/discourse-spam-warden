# frozen_string_literal: true

module DiscourseSpamWarden
  class SubmitReport
    include Service::Base

    params do
      attribute :user_id, :integer
      attribute :token, :string
      attribute :confirmed, :boolean
      validates :user_id, presence: true
      validates :token, presence: true, length: { maximum: 4096 }
      validates :confirmed, inclusion: { in: [true] }
    end

    policy :can_submit
    policy :configured
    model :user
    model :candidate
    model :submission, :reserve_submission
    step :enqueue
    step :log_approval

    private

    def can_submit(guardian:)
      guardian.is_admin? && guardian.user.human?
    end

    def configured
      SubmissionCandidate.configured?
    end

    def fetch_user(params:)
      User.find_by(id: params.user_id)
    end

    def fetch_candidate(params:, user:, guardian:)
      SubmissionCandidate.from_token(user, guardian.user, params.token)
    end

    def reserve_submission(candidate:, guardian:)
      Submission.reserve(candidate, guardian.user)
    end

    def enqueue(submission:)
      Jobs.enqueue(:spam_warden_submit, submission_id: submission.id)
    end

    def log_approval(submission:, guardian:)
      StaffActionLogger.new(guardian.user).log_custom(
        "spam_warden_submit_approved",
        submission_id: submission.id,
        user_id: submission.user_id,
      )
    end
  end
end
