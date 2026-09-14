# frozen_string_literal: true

module Jobs
  class SpamWardenCleanup < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      DiscourseSpamWarden::Scan.expire!
      DiscourseSpamWarden::Submission.where.not(user_id: User.select(:id)).in_batches.delete_all
      DiscourseSpamWarden::Account.where.not(user_id: User.select(:id)).in_batches.delete_all
      DiscourseSpamWarden::Scan.where.not(user_id: User.select(:id)).in_batches.delete_all
    end
  end
end
