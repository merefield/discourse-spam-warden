# frozen_string_literal: true

module DiscourseSpamWarden
  class Scan < ActiveRecord::Base
    self.table_name = "spam_warden_scans"
    belongs_to :user
    belongs_to :reviewable, optional: true
    validates :user_id, :source, :status, :decision, presence: true

    scope :latest, -> { order(created_at: :desc, id: :desc) }

    def self.latest_for_users(user_ids)
      return [] if user_ids.empty?

      find_by_sql([<<~SQL, { user_ids: user_ids }])
          SELECT latest_scan.*
          FROM users
          JOIN LATERAL (
            SELECT scans.user_id, scans.status, scans.decision, scans.created_at, scans.policy
            FROM spam_warden_scans AS scans
            WHERE scans.user_id = users.id
            ORDER BY scans.created_at DESC, scans.id DESC
            LIMIT 1
          ) AS latest_scan ON true
          WHERE users.id IN (:user_ids)
        SQL
    end

    def self.expire!
      expired = where("created_at < ?", SiteSetting.spam_warden_retention_days.days.ago)
      expired.where.not(reviewable_id: Reviewable.pending.select(:id)).in_batches.delete_all
      expired.where(reviewable_id: nil).in_batches.delete_all
    end
  end
end

# == Schema Information
#
# Table name: spam_warden_scans
#
#  id            :bigint           not null, primary key
#  action_taken  :string           default("none"), not null
#  decision      :string           not null
#  error_code    :string
#  evidence      :jsonb            not null
#  policy        :jsonb            not null
#  source        :string           not null
#  status        :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  reviewable_id :bigint
#  user_id       :bigint           not null
#
# Indexes
#
#  idx_spam_warden_scans_latest                       (user_id,created_at DESC,id DESC)
#  idx_spam_warden_scans_source_latest                (user_id,source,created_at DESC,id DESC)
#  index_spam_warden_scans_on_created_at              (created_at)
#  index_spam_warden_scans_on_reviewable_id           (reviewable_id)
#  index_spam_warden_scans_on_user_id_and_created_at  (user_id,created_at)
#
