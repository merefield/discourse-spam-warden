# frozen_string_literal: true

module Jobs
  # Persisted MiniScheduler entries need the scheduled API, but must not recur.
  class SpamGuardSubmissionRecovery < ::Jobs::Scheduled
    def execute(args)
      SpamWardenSubmissionRecovery.new.execute(args)
    end
  end
end
