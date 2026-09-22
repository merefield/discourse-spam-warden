# frozen_string_literal: true

module DiscourseSpamWarden
  class AiIntegration
    POST_LIMIT = 100
    RESULT_LIMIT = 10
    HISTORY_WINDOW = 30.days

    def self.available?
      SiteSetting.spam_warden_ai_integration && log_models.present?
    end

    def self.extension_values(name, defaults)
      values =
        ActiveRecord::Base.transaction(requires_new: true) do
          DiscoursePluginRegistry.apply_modifier(name, defaults.dup)
        end
      raise TypeError unless values.is_a?(Array)
      values
    rescue StandardError => error
      Rails.logger.warn("Spam Warden classifier modifier #{name} unavailable (#{error.class})")
      defaults
    end

    def self.provider_result(model, fallback: [])
      # A provider SQL failure must not abort an enclosing account-check transaction.
      result = ActiveRecord::Base.transaction(requires_new: true) { yield }
      result.nil? ? fallback : result
    rescue StandardError => error
      Rails.logger.warn(
        "Spam Warden classifier provider #{model.name} unavailable (#{error.class})",
      )
      fallback
    end

    def self.log_models
      models = defined?(::AiSpamLog) ? [::AiSpamLog] : []
      extension_values(:spam_warden_classifier_log_models, models).uniq.select do |model|
        provider_result(model, fallback: false) do
          model.is_a?(Class) && model < ActiveRecord::Base && model.table_exists?
        end
      end
    end

    def self.posts(user)
      Post
        .with_deleted
        .joins(topic: :category)
        .where(user: user, post_type: Post.types[:regular])
        .where(topics: { archetype: Archetype.default })
        .where(categories: { read_restricted: false })
        .where("posts.created_at >= ?", HISTORY_WINDOW.ago)
        .order(id: :desc)
        .limit(POST_LIMIT)
    end

    def self.latest_logs(user, model = ::AiSpamLog)
      latest =
        model
          .where(post_id: posts(user).select(:id))
          .where("#{model.table_name}.created_at >= ?", HISTORY_WINDOW.ago)
          .select(
            "DISTINCT ON (post_id) id, post_id, reviewable_id, is_spam, LEFT(reason, 2000) AS reason, created_at, error",
          )
          .order(:post_id, id: :desc)
      model.from(latest, model.table_name).order(created_at: :desc, id: :desc)
    end

    def self.snapshot(user, guardian:)
      return nil unless guardian.is_admin? && available?
      logs =
        log_models
          .flat_map do |model|
            provider_result(model) { latest_logs(user, model).limit(RESULT_LIMIT).to_a }
          end
          .sort_by { |log| [log.created_at, log.id] }
          .reverse
          .uniq(&:post_id)
          .take(RESULT_LIMIT)
      post_by_id =
        posts(user)
          .where(id: logs.map(&:post_id))
          .select(:id, :topic_id, :post_number)
          .index_by(&:id)
      spam_scores = ReviewableScore.where(reviewable_score_type: ReviewableScore.types[:spam])
      reviews =
        ReviewableFlaggedPost
          .where(
            target_id: logs.map(&:post_id),
            target_created_by: user,
            id: spam_scores.select(:reviewable_id),
          )
          .order(id: :desc)
          .to_a
      reviews_by_id = reviews.index_by(&:id)
      fallback_reviews = reviews.group_by(&:target_id).transform_values(&:first)
      staff = User.where("id > 0 AND (admin OR moderator)").select(:id)
      decisions =
        ReviewableScore
          .where(
            reviewable_id: reviews.map(&:id),
            reviewable_score_type: ReviewableScore.types[:spam],
            reviewed_by_id: staff,
          )
          .where(status: %i[agreed disagreed ignored])
          .order(reviewed_at: :desc, id: :desc)
          .group_by(&:reviewable_id)
      {
        "entries" =>
          logs.filter_map do |log|
            post = post_by_id[log.post_id]
            next unless post && guardian.can_see?(post)
            review =
              log.reviewable_id ? reviews_by_id[log.reviewable_id] : fallback_reviews[post.id]
            review = nil if review && review.target_id != post.id
            outcome =
              if review&.pending?
                "pending"
              elsif decision = decisions[review&.id]&.first
                {
                  "agreed" => "confirmed",
                  "disagreed" => "rejected",
                  "ignored" => "ignored",
                }.fetch(decision.status)
              else
                "unreviewed"
              end
            {
              "post_id" => post.id,
              "post_url" => "/t/#{post.topic_id}/#{post.post_number}",
              "is_spam" => log.is_spam,
              "reason" => log.reason,
              "checked_at" => log.created_at,
              "reviewable_id" => review&.id,
              "outcome" => outcome,
              "has_error" => log.error.present?,
            }
          end,
      }
    end

    def self.pending_review(user)
      return unless available?
      review_ids =
        log_models
          .flat_map do |model|
            provider_result(model) do
              latest_logs(user, model).where(is_spam: true, error: [nil, ""]).pluck(:reviewable_id)
            end
          end
          .compact
          .uniq
      ReviewableFlaggedPost
        .pending
        .where(target_created_by: user, id: review_ids)
        .where(target_id: posts(user).select(:id))
        .order(id: :desc)
        .lock
        .first
    end

    def self.ai_review_ids(reviews)
      return [] unless available? && reviews.present?
      log_models
        .flat_map do |model|
          provider_result(model) do
            model
              .where(
                post_id: reviews.map(&:target_id),
                reviewable_id: reviews.map(&:id),
                is_spam: true,
              )
              .distinct
              .pluck(:reviewable_id)
          end
        end
        .uniq
    end

    def self.enqueue_reconciliation(review)
      return unless available? && review.is_a?(ReviewableFlaggedPost) && review.pending?
      bot_ids =
        (
          if SiteSetting.respond_to?(:ai_spam_detection_user_id)
            [SiteSetting.ai_spam_detection_user_id.to_i]
          else
            []
          end
        )
      bot_ids =
        extension_values(:spam_warden_classifier_bot_ids, bot_ids)
          .select { |id| id.is_a?(Integer) && id.negative? }
          .uniq
      return if bot_ids.empty?
      unless review
               .reviewable_scores
               .where(
                 user_id: bot_ids,
                 reviewable_score_type: ReviewableScore.types[:spam],
                 status: :pending,
               )
               .exists?
        return
      end
      # AI links its log after creating the flag, within the same transaction.
      DB.after_commit do
        Jobs.enqueue_in(5.seconds, :spam_warden_reconcile_ai, user_id: review.target_created_by_id)
      end
    end

    def self.reconcile(user)
      return unless user && available?
      DistributedMutex.synchronize("spam_warden:user:#{user.id}") do
        user.with_lock do
          review = pending_review(user)
          return unless review
          review.with_lock do
            return unless review.pending?
            ReviewableSpamWarden
              .pending
              .where(target: user)
              .find_each do |duplicate|
                duplicate.with_lock do
                  next unless duplicate.pending?
                  Scan.where(reviewable: duplicate).update_all(reviewable_id: review.id)
                  duplicate.update!(
                    payload: duplicate.payload.merge("ai_reviewable_id" => review.id),
                  )
                  duplicate.transition_to(:ignored, Discourse.system_user)
                  Jobs.enqueue(
                    :notify_reviewable,
                    reviewable_id: duplicate.id,
                    performing_username: Discourse.system_user.username,
                  )
                end
              end
          end
        end
      end
    end
  end
end
