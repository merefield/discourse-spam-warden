# frozen_string_literal: true

module Jobs
  # Keep jobs queued before the rename executable after an upgrade.
  class SpamGuardSubmit < ::Jobs::Base
    def execute(args)
      SpamWardenSubmit.new.execute(args)
    end
  end
end
