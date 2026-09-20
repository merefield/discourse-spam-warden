# frozen_string_literal: true

module Jobs
  # Persisted MiniScheduler entries need the scheduled API, but must not recur.
  class SpamGuardCleanup < ::Jobs::Scheduled
    def execute(args)
      SpamWardenCleanup.new.execute(args)
    end
  end
end
