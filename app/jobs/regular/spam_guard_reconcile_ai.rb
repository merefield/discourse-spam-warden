# frozen_string_literal: true

module Jobs
  # Keep jobs queued before the rename executable after an upgrade.
  class SpamGuardReconcileAi < ::Jobs::Base
    def execute(args)
      SpamWardenReconcileAi.new.execute(args)
    end
  end
end
