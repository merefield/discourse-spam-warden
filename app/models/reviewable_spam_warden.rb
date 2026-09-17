# frozen_string_literal: true

class ReviewableSpamWarden < Reviewable
  attr_writer :spam_warden_scan

  def spam_warden_scan
    return @spam_warden_scan if defined?(@spam_warden_scan)
    @spam_warden_scan = DiscourseSpamWarden::Scan.find_by(id: payload["scan_id"])
    @spam_warden_scan.association(:user).target = target if @spam_warden_scan
    @spam_warden_scan
  end

  def build_actions(actions, guardian, args)
    return unless pending? && guardian.is_staff? && guardian.user.human? && target && !target.staff?
    if guardian.is_admin?
      actions.add(:allow_account) do |action|
        action.icon = "user-check"
        action.label = "spam_warden.allow"
      end
    end
    if target.silenced? || target.suspended?
      actions.add(:confirm_restriction) do |action|
        action.icon = "user-check"
        action.label = "spam_warden.confirm_restriction"
      end
    elsif guardian.can_silence_user?(target)
      actions.add(:silence_account) do |action|
        action.icon = "user-slash"
        action.label = "spam_warden.confirm"
        action.confirm_message = "spam_warden.confirm_message"
      end
    end
  end

  def perform_allow_account(actor, _args)
    DiscourseSpamWarden::Moderation.allow(target, actor, reviewable: self)
    create_result(:success, :approved)
  end

  def perform_silence_account(actor, _args)
    changed =
      target.with_lock { DiscourseSpamWarden::Moderation.silence(target, actor, reviewable: self) }
    return create_result(:success, :rejected) if changed
    errors.add(:base, I18n.t("spam_warden.silence_failed"))
    create_result(:failure) { |result| result.errors = errors }
  end

  def perform_confirm_restriction(actor, _args)
    raise Discourse::InvalidAccess unless actor.staff? && actor.human?
    target.with_lock do
      if !target.staff? && (target.silenced? || target.suspended?)
        return create_result(:success, :rejected)
      end
    end
    errors.add(:base, I18n.t("spam_warden.silence_failed"))
    create_result(:failure) { |result| result.errors = errors }
  end

  def serializer
    ReviewableSpamWardenSerializer
  end
end

# == Schema Information
#
# Table name: reviewables
#
#  id                      :bigint           not null, primary key
#  force_review            :boolean          default(FALSE), not null
#  latest_score            :datetime
#  payload                 :json
#  potential_spam          :boolean          default(FALSE), not null
#  potentially_illegal     :boolean          default(FALSE)
#  reject_reason           :text
#  reviewable_by_moderator :boolean          default(FALSE), not null
#  score                   :float            default(0.0), not null
#  status                  :integer          default("pending"), not null
#  target_type             :string
#  type                    :string           not null
#  type_source             :string           default("unknown"), not null
#  version                 :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  category_id             :integer
#  created_by_id           :integer          not null
#  target_created_by_id    :integer
#  target_id               :integer
#  topic_id                :integer
#
# Indexes
#
#  idx_reviewables_score_desc_created_at_desc                  (score,created_at)
#  index_reviewables_on_reviewable_by_group_id                 (reviewable_by_group_id)
#  index_reviewables_on_status_and_created_at                  (status,created_at)
#  index_reviewables_on_status_and_score                       (status,score)
#  index_reviewables_on_status_and_type                        (status,type)
#  index_reviewables_on_target_created_by_id                   (target_created_by_id)
#  index_reviewables_on_target_id_where_post_type_eq_post      (target_id) WHERE ((target_type)::text = 'Post'::text)
#  index_reviewables_on_topic_id_and_status_and_created_by_id  (topic_id,status,created_by_id)
#  index_reviewables_on_type_and_target_id                     (type,target_id) UNIQUE
#
