# frozen_string_literal: true

module Jobs
  class SpamWardenReconcileAi < ::Jobs::Base
    def execute(args)
      DiscourseSpamWarden::AiIntegration.reconcile(User.find_by(id: args[:user_id]))
    end
  end
end
