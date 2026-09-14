# frozen_string_literal: true

module DiscourseSpamWarden
  class LocalSignals
    POST_LIMIT = 100
    MIN_DUPLICATE_LENGTH = 40
    DUPLICATE_THRESHOLD = 3
    BURST_THRESHOLD = 5
    TOPIC_THRESHOLD = 3
    POST_WINDOW = 24.hours
    BURST_WINDOW = 10.minutes
    HISTORY_WINDOW = 30.days
    HISTORY_LIMIT = 3
    POSTING_CAP = 25

    def self.snapshot(user, weights: Policy.weights)
      return { "enabled" => false, "adjustment" => 0 } unless SiteSetting.spam_warden_local_signals

      recent_posts =
        Post
          .joins(topic: :category)
          .where(user: user, post_type: Post.types[:regular])
          .where(topics: { archetype: Archetype.default, deleted_at: nil })
          .where(categories: { read_restricted: false })
          .where(created_at: POST_WINDOW.ago..Time.current)
          .order(created_at: :desc, id: :desc)
          .limit(POST_LIMIT)
          .select(:topic_id, :created_at, :raw)
      posts =
        Post
          .unscoped
          .from(recent_posts, :recent_posts)
          .pluck(
            "recent_posts.topic_id",
            "recent_posts.created_at",
            Arel.sql(
              "CASE WHEN LENGTH(recent_posts.raw) >= #{MIN_DUPLICATE_LENGTH} THEN MD5(recent_posts.raw) END",
            ),
          )

      duplicate_posts =
        posts
          .select { |post| post[2] }
          .group_by { |post| post[2] }
          .values
          .select { |group| group.map(&:first).uniq.size >= TOPIC_THRESHOLD }
          .map(&:size)
          .max || 0
      recent = posts.select { |post| post[1] >= BURST_WINDOW.ago }
      burst_topics = recent.map(&:first).uniq.size
      duplicate_points = duplicate_posts >= DUPLICATE_THRESHOLD ? 20 : 0
      burst_points = recent.size >= BURST_THRESHOLD && burst_topics >= TOPIC_THRESHOLD ? 15 : 0
      posting_points = [duplicate_points + burst_points, POSTING_CAP].min

      staff = User.where("id > 0").where("admin OR moderator").select(:id)
      confirmed_scores =
        ReviewableScore.where("reviewable_scores.reviewable_id = reviewables.id").where(
          status: ReviewableScore.statuses[:agreed],
          reviewable_score_type: ReviewableScore.types[:spam],
          reviewed_by_id: staff,
          reviewed_at: HISTORY_WINDOW.ago..Time.current,
        )
      points_per_post = weights.fetch("confirmed_spam")
      history_limit =
        (
          if points_per_post.positive?
            [HISTORY_LIMIT, (100.fdiv(points_per_post)).ceil].max
          else
            HISTORY_LIMIT
          end
        )
      confirmed_posts =
        ReviewableFlaggedPost
          .approved
          .where(target_created_by: user)
          .where(confirmed_scores.arel.exists)
          .limit(history_limit)
          .pluck(:target_id)
          .size
      history_points = confirmed_posts * points_per_post

      {
        "enabled" => true,
        "duplicate_posts" => duplicate_posts,
        "duplicate_points" => duplicate_points,
        "burst_posts" => recent.size,
        "burst_topics" => burst_topics,
        "burst_points" => burst_points,
        "posting_points" => posting_points,
        "confirmed_spam_posts" => confirmed_posts,
        "history_points" => history_points,
        "adjustment" => posting_points + history_points,
        "posts_sampled" => posts.size,
      }
    end

    def self.enqueue(user, delay: 1.minute, attempt: 0)
      return unless DiscourseSpamWarden.enabled? && SiteSetting.spam_warden_local_signals
      unless user&.human? && !user.staff? && user.created_at >= 7.days.ago && user.trust_level <= 1
        return
      end
      return if Account.exists?(user: user, allowed: true)

      ActivityQueue.enqueue(user.id, delay: delay, attempt: attempt)
    end
  end
end
