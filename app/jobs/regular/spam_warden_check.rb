# frozen_string_literal: true

module Jobs
  class SpamWardenCheck < ::Jobs::Base
    def execute(args)
      started_at = Time.current
      if args[:source] == "activity"
        DiscourseSpamWarden::ActivityQueue.release(args[:user_id], args[:activity_token])
      end
      result =
        DiscourseSpamWarden::CheckAccount.call(
          params: args.slice(:user_id, :source),
          guardian: Discourse.system_user.guardian,
        )
      attempt = args.fetch(:attempt, 0).to_i
      if result.success? && result[:scan]&.status == "unknown" && attempt < 2
        if args[:source] == "activity"
          DiscourseSpamWarden::LocalSignals.enqueue(
            User.find_by(id: args[:user_id]),
            delay: (attempt + 1).minutes,
            attempt: attempt + 1,
          )
        else
          Jobs.enqueue_in(
            (attempt + 1).minutes,
            :spam_warden_check,
            **args.merge(attempt: attempt + 1),
          )
        end
      elsif args[:source] == "activity" && result.success? && result[:scan] &&
            result[:scan].status != "unknown" && result[:scan].created_at < started_at
        DiscourseSpamWarden::LocalSignals.enqueue(User.find_by(id: args[:user_id]))
      end
    end
  end
end
