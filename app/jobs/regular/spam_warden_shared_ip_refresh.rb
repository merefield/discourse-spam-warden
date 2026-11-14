# frozen_string_literal: true

module Jobs
  class SpamWardenSharedIpRefresh < ::Jobs::Base
    def execute(args)
      return unless DiscourseSpamWarden.enabled? && DiscourseSpamWarden::SharedIp.enabled?
      user = User.find_by(id: args[:user_id])
      return unless user
      members = DiscourseSpamWarden::SharedIp.matches(DiscourseSpamWarden::SharedIp.addresses(user))
      ids =
        members
          .where.not(id: user.id)
          .where("users.id > ?", args.fetch(:after_id, 0))
          .order(:id)
          .limit(100)
          .pluck(:id)
      ids.each do |id|
        target = User.find_by(id: id)
        DiscourseSpamWarden::Checker.call(target, source: "shared_ip") if target
      end
      if ids.size == 100
        Jobs.enqueue(:spam_warden_shared_ip_refresh, user_id: user.id, after_id: ids.last)
      end
    end
  end
end
