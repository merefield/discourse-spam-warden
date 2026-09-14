# frozen_string_literal: true

require "digest"
require "ipaddr"

module DiscourseSpamWarden
  class SubmissionCandidate
    IPV6_GLOBAL_UNICAST = IPAddr.new("2000::/3")
    # Reporting excludes multicast and transitional/documentation space beyond core's SSRF filter.
    NON_REPORTABLE_RANGES =
      %w[192.88.99.0/24 224.0.0.0/4 2002::/16 3fff::/20].map { |range| IPAddr.new(range) }.freeze
    EVIDENCE_LIMIT = 2000
    PREVIEW_LIFETIME = 10.minutes
    HISTORY_WINDOW = 30.days
    attr_reader :user, :post, :review, :payload

    def self.configured?
      SiteSetting.spam_warden_submissions_enabled &&
        SiteSetting.spam_warden_submission_api_key.present?
    end

    def self.reviews(user)
      staff = User.where("id > 0 AND (admin OR moderator)").select(:id)
      scores =
        ReviewableScore.where("reviewable_scores.reviewable_id = reviewables.id").where(
          status: ReviewableScore.statuses[:agreed],
          reviewable_score_type: ReviewableScore.types[:spam],
          reviewed_by_id: staff,
          reviewed_at: HISTORY_WINDOW.ago..Time.current,
        )
      ReviewableFlaggedPost.approved.where(target_created_by: user).where(scores.arel.exists)
    end

    def self.latest(user)
      reviews(user)
        .order(id: :desc)
        .limit(10)
        .each do |review|
          candidate = for_post(user, review.target_id, review.id)
          return candidate if candidate
        end
      nil
    end

    def self.for_post(user, post_id, reviewable_id)
      unless user&.human? && !user.staff? && user.active? && !user.staged? && user.email_confirmed?
        return
      end
      return if Account.exists?(user: user, allowed: true)
      review = reviews(user).find_by(id: reviewable_id, target_id: post_id)
      return unless review
      post =
        Post.with_deleted.find_by(id: post_id, user_id: user.id, post_type: Post.types[:regular])
      return unless post && post.raw.present?
      topic = Topic.with_deleted.find_by(id: post.topic_id, archetype: Archetype.default)
      return unless topic && Category.exists?(id: topic.category_id, read_restricted: false)
      return unless public_ip?(user.registration_ip_address)
      new(user, post, review)
    end

    def self.public_ip?(value)
      return false if value.blank?
      ip = IPAddr.new(value.to_s)
      ip = ip.native if ip.ipv4_mapped?
      return false if ip.ipv6? && !IPV6_GLOBAL_UNICAST.include?(ip)
      return false if NON_REPORTABLE_RANGES.any? { |range| range.include?(ip) }
      FinalDestination::SSRFDetector.ip_allowed?(ip)
    rescue IPAddr::InvalidAddressError
      false
    end

    def self.verifier
      Rails.application.message_verifier("spam_warden_submission")
    end

    def self.from_token(user, actor, token)
      data = verifier.verified(token, purpose: "spam_warden_submission")
      return unless data.is_a?(Hash) && data["user_id"] == user.id && data["actor_id"] == actor.id
      candidate = for_post(user, data["post_id"], data["reviewable_id"])
      candidate if candidate && candidate.fingerprint == data["fingerprint"]
    end

    def initialize(user, post, review)
      @user, @post, @review = user, post, review
      @payload = {
        "username" => user.username,
        "email" => user.email,
        "ip_addr" => user.registration_ip_address.to_s,
        "evidence" =>
          "#{Discourse.base_url}/t/#{post.topic_id}/#{post.post_number}\n\n#{post.raw.first(EVIDENCE_LIMIT)}",
      }
    end

    def fingerprint
      Digest::SHA256.hexdigest([payload, post.updated_at.to_f, review.id].to_json)
    end

    def preview_token(actor)
      self.class.verifier.generate(
        {
          "user_id" => user.id,
          "actor_id" => actor.id,
          "post_id" => post.id,
          "reviewable_id" => review.id,
          "fingerprint" => fingerprint,
        },
        expires_in: PREVIEW_LIFETIME,
        purpose: "spam_warden_submission",
      )
    end
  end
end
