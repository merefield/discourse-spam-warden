# frozen_string_literal: true

module Jobs
  # Keep jobs queued before the rename executable after an upgrade.
  class SpamGuardCleanup < ::Jobs::Base
    def execute(args)
      SpamWardenCleanup.new.execute(args)
    end
  end
end
