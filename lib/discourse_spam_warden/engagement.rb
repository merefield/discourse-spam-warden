# frozen_string_literal: true

module DiscourseSpamWarden
  class Engagement
    def self.snapshot(user, source:, weights: Policy.weights)
      stats =
        UserStat.select(
          :topics_entered,
          :posts_read_count,
          :time_read,
          :days_visited,
          :post_count,
        ).find_by(user_id: user.id)
      return { "level" => "unavailable", "adjustment" => 0, "available" => false } unless stats

      topics = [stats.topics_entered, 0].max
      posts = [stats.posts_read_count, 0].max
      seconds = [stats.time_read, 0].max
      days = [stats.days_visited, 0].max
      level, adjustment =
        if topics >= 5 && posts >= 30 && seconds >= 600 && days >= 2
          ["sustained", weights.fetch("reading_sustained")]
        elsif topics >= 1 && posts >= 3 && seconds >= 60
          ["meaningful", weights.fetch("reading_meaningful")]
        elsif topics.positive? || posts.positive? || seconds.positive?
          ["limited", weights.fetch("reading_limited")]
        elsif stats.post_count.positive? ||
              (source != "registration" && user.created_at <= 1.hour.ago)
          ["none", weights.fetch("no_reading")]
        else
          ["new_account", 0]
        end

      {
        "available" => true,
        "topics_viewed" => topics,
        "posts_read" => posts,
        "reading_seconds" => seconds,
        "reading_minutes" => (seconds / 60.0).round(1),
        "days_visited" => days,
        "level" => level,
        "adjustment" => adjustment,
      }
    end
  end
end
