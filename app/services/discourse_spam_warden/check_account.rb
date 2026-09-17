# frozen_string_literal: true

module DiscourseSpamWarden
  class CheckAccount
    include Service::Base

    params do
      attribute :user_id, :integer
      attribute :source, :string, default: "manual"
      validates :user_id, presence: true
      validates :source, inclusion: { in: %w[manual registration recheck activity] }
    end

    policy :enabled
    model :user
    policy :can_check_account
    model :scan, :check_account, optional: true

    private

    def enabled
      DiscourseSpamWarden.enabled?
    end

    def fetch_user(params:)
      User.find_by(id: params.user_id)
    end

    def can_check_account(guardian:, user:, params:)
      return false if user.staff? || !user.human?
      if params.source == "manual"
        guardian.is_admin? && guardian.user.human?
      else
        guardian.user.id == Discourse.system_user.id
      end
    end

    def check_account(user:, params:)
      Checker.call(user, source: params.source)
    end
  end
end
