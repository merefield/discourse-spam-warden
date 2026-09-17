# frozen_string_literal: true

module DiscourseSpamWarden
  class UpdateException
    include Service::Base

    params do
      attribute :user_id, :integer
      attribute :allowed, :boolean
      validates :user_id, presence: true
      validates :allowed, inclusion: { in: [true, false] }
    end

    model :user
    policy :can_manage_exception
    step :update_exception

    private

    def fetch_user(params:)
      User.find_by(id: params.user_id)
    end

    def can_manage_exception(guardian:, user:)
      guardian.is_admin? && guardian.user.human? && !user.staff?
    end

    def update_exception(user:, params:, guardian:)
      if params.allowed
        user.with_lock do
          reviewable = ReviewableSpamWarden.pending.find_by(target: user)
          if reviewable
            reviewable.perform(guardian.user, :allow_account)
          else
            Moderation.allow(user, guardian.user)
          end
        end
      else
        user.with_lock do
          Account.where(user: user).update_all(
            allowed: false,
            allowed_by_id: nil,
            updated_at: Time.current,
          )
          StaffActionLogger.new(guardian.user).log_custom(
            "spam_warden_remove_exception",
            user_id: user.id,
          )
        end
      end
    end
  end
end
