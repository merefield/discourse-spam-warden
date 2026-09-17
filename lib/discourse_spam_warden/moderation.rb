# frozen_string_literal: true

module DiscourseSpamWarden
  class Moderation
    def self.silence(user, actor, reviewable:)
      raise Discourse::InvalidAccess unless actor.guardian.can_silence_user?(user)
      return false if user.silenced? || user.suspended? || user.staff?
      silencer =
        UserSilencer.new(
          user,
          actor,
          keep_posts: true,
          reviewable_id: reviewable.id,
          reason:
            I18n.t(
              actor.human? ? "spam_warden.manual_silence_reason" : "spam_warden.silence_reason",
              reviewable_id: reviewable.id,
            ),
        )
      if silencer.silence
        account = Account.find_or_create_by!(user: user)
        account.update!(
          silence_history_id: silencer.user_history.id,
          silenced_till: user.silenced_till,
        )
        true
      end
    end

    def self.allow(user, actor, reviewable: nil)
      raise Discourse::InvalidAccess unless actor.guardian.is_admin? && actor.human? && !user.staff?
      user.with_lock do
        account = Account.find_or_create_by!(user: user)
        UserSilencer.unsilence(user, actor, reviewable_id: reviewable&.id) if account.owns_silence?
        account.update!(
          allowed: true,
          allowed_by_id: actor.id,
          silence_history_id: nil,
          silenced_till: nil,
        )
        StaffActionLogger.new(actor).log_custom("spam_warden_allow", user_id: user.id)
      end
    end
  end
end
