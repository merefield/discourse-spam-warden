# frozen_string_literal: true

module DiscourseSpamWarden
  class Submission < ActiveRecord::Base
    self.table_name = "spam_warden_submissions"
    PROTECTED_STATUSES = %w[pending sending submitted unknown].freeze
    MAX_ATTEMPTS = 3
    APPROVAL_LIFETIME = 1.hour
    belongs_to :user
    belongs_to :actor, class_name: "User"
    validates :user_id, uniqueness: true
    validates :status,
              inclusion: {
                in: %w[pending sending submitted rejected unknown failed cancelled],
              }

    def self.reserve(candidate, actor)
      candidate.user.with_lock do
        record = find_or_initialize_by(user: candidate.user)
        return record if record.persisted? && PROTECTED_STATUSES.include?(record.status)
        current =
          SubmissionCandidate.for_post(candidate.user, candidate.post.id, candidate.review.id)
        unless current && current.fingerprint == candidate.fingerprint
          raise Discourse::InvalidAccess
        end
        record.assign_attributes(
          actor: actor,
          post_id: candidate.post.id,
          reviewable_id: candidate.review.id,
          fingerprint: candidate.fingerprint,
          status: "pending",
          attempts: 0,
          approved_at: Time.current,
          last_attempt_at: nil,
          completed_at: nil,
          error_code: nil,
        )
        record.add_event("approved")
        record.save
        record
      end
    end

    def add_event(state)
      self.events =
        (
          events + [{ "status" => state, "at" => Time.current.iso8601, "actor_id" => actor_id }]
        ).last(20)
    end

    def candidate
      return unless SubmissionCandidate.configured? && approved_at >= APPROVAL_LIFETIME.ago
      return unless actor&.human? && actor.admin?
      current = SubmissionCandidate.for_post(user, post_id, reviewable_id)
      current if current && current.fingerprint == fingerprint
    end

    def finish!(state, code = nil)
      self.status = state
      self.error_code = code
      self.completed_at = %w[pending sending].include?(state) ? nil : Time.current
      add_event(state)
      save!
    end
  end
end

# == Schema Information
#
# Table name: spam_warden_submissions
#
#  id              :bigint           not null, primary key
#  approved_at     :datetime         not null
#  attempts        :integer          default(0), not null
#  completed_at    :datetime
#  error_code      :string
#  events          :jsonb            not null
#  fingerprint     :string(64)       not null
#  last_attempt_at :datetime
#  status          :string           default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  actor_id        :bigint           not null
#  post_id         :bigint           not null
#  reviewable_id   :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_spam_warden_submissions_on_status_and_updated_at  (status,updated_at)
#  index_spam_warden_submissions_on_user_id                (user_id) UNIQUE
#
