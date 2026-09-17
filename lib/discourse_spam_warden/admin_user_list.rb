# frozen_string_literal: true

module DiscourseSpamWarden
  module AdminUserList
    def self.preload(users, guardian)
      return users unless guardian&.is_admin?

      ids = users.map(&:id)
      return users if ids.empty?

      scans = DiscourseSpamWarden::Scan.latest_for_users(ids).index_by(&:user_id)
      exceptions =
        DiscourseSpamWarden::Account.where(user_id: ids, allowed: true).pluck(:user_id).to_set

      users.each do |user|
        scan = scans[user.id]
        user.instance_variable_set(
          :@spam_warden_summary,
          {
            exempt: exceptions.include?(user.id),
            scan:
              scan &&
                {
                  status: scan.status,
                  decision: scan.decision,
                  checked_at: scan.created_at,
                  score:
                    (
                      if scan.status == "checked" && scan.policy.dig("assessment", "scored")
                        scan.policy.dig("assessment", "score")
                      else
                        nil
                      end
                    ),
                  scored:
                    scan.status == "checked" && scan.policy.dig("assessment", "scored") == true,
                },
          },
        )
      end
      users
    end
  end
end
