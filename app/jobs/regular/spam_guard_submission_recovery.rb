# frozen_string_literal: true

module Jobs
  # Keep jobs queued before the rename executable after an upgrade.
  class SpamGuardSubmissionRecovery < ::Jobs::Base
    def execute(args)
      SpamWardenSubmissionRecovery.new.execute(args)
    end
  end
end
